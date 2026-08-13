#!/usr/bin/env node
// Claude Code ステータスライン。stdin の JSON セッション情報を整形する。
// 仕様: https://docs.claude.com/en/docs/claude-code/statusline
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = childProcess;

const CACHE_TTL_MS = 5 * 60 * 1000;
const RETRY_DELAY_MS = 60 * 1000;
const CODEX_TIMEOUT_MS = 5_000;
const FIVE_HOURS_MINUTES = 5 * 60;
const SEVEN_DAYS_MINUTES = 7 * 24 * 60;
const CACHE_PATH = path.join(
  process.env.LOCALAPPDATA || os.tmpdir(),
  "agent-config",
  "claudex",
  "statusline-rate-limit.json",
);

function readRateLimitCache(cachePath) {
  try {
    return JSON.parse(fs.readFileSync(cachePath, "utf8"));
  } catch {
    return null;
  }
}

function writeRateLimitCache(cachePath, value) {
  try {
    fs.mkdirSync(path.dirname(cachePath), { recursive: true });
    const temporary = `${cachePath}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(value), "utf8");
    fs.renameSync(temporary, cachePath);
  } catch {
    // キャッシュ失敗でstatuslineを失敗させない。
  }
}

function validUsagePercent(value) {
  return Number.isFinite(value) && value >= 0 && value <= 100;
}

function sanitizeCodexLimits(value) {
  const limits = {};
  if (validUsagePercent(value?.fiveHour)) limits.fiveHour = value.fiveHour;
  if (validUsagePercent(value?.sevenDay)) limits.sevenDay = value.sevenDay;
  return Object.keys(limits).length > 0 ? limits : null;
}

function normalizeCodexRateLimits(rateLimits) {
  const limits = {};
  for (const limit of [rateLimits?.primary, rateLimits?.secondary]) {
    if (!validUsagePercent(limit?.usedPercent)) continue;
    if (limit.windowDurationMins === FIVE_HOURS_MINUTES) {
      limits.fiveHour = limit.usedPercent;
    }
    if (limit.windowDurationMins === SEVEN_DAYS_MINUTES) {
      limits.sevenDay = limit.usedPercent;
    }
  }
  return Object.keys(limits).length > 0 ? limits : null;
}

function elapsedWithin(now, timestamp, duration) {
  const elapsed = now - timestamp;
  return Number.isFinite(timestamp) && elapsed >= 0 && elapsed < duration;
}

async function getCodexRateLimit({
  cachePath = CACHE_PATH,
  now = Date.now(),
  fetchImpl = fetchCodexRateLimit,
} = {}) {
  const retryCachePath = `${cachePath}.retry`;
  const cache = readRateLimitCache(cachePath);
  const retryCache = readRateLimitCache(retryCachePath);
  const cachedLimits = sanitizeCodexLimits(cache);
  if (cachedLimits && elapsedWithin(now, cache.fetchedAt, CACHE_TTL_MS)) {
    return cachedLimits;
  }
  if (elapsedWithin(now, retryCache?.attemptedAt, RETRY_DELAY_MS)) {
    return null;
  }

  try {
    const limits = sanitizeCodexLimits(await fetchImpl());
    if (!limits) throw new Error("Codex rate limit is missing");
    writeRateLimitCache(cachePath, {
      ...limits,
      fetchedAt: now,
      attemptedAt: now,
    });
    return limits;
  } catch {
    writeRateLimitCache(retryCachePath, { attemptedAt: now });
    return null;
  }
}

function fetchCodexRateLimit({
  spawnImpl = childProcess.spawn,
  timeoutMs = CODEX_TIMEOUT_MS,
  platform = process.platform,
} = {}) {
  return new Promise((resolve, reject) => {
    let child;
    let timer;
    let buffer = "";
    let settled = false;

    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      if (child) child.kill();
      if (error) reject(error);
      else resolve(value);
    };

    const send = (message) => {
      try {
        child.stdin.write(`${JSON.stringify(message)}\n`);
      } catch (error) {
        finish(error);
      }
    };

    const handleMessage = (message) => {
      if (message.id === 1) {
        if (message.error) return finish(new Error("Codex initialize failed"));
        send({ method: "account/rateLimits/read", id: 2, params: {} });
        return;
      }
      if (message.id !== 2) return;
      if (message.error) return finish(new Error("Codex rate limit failed"));

      const limits = normalizeCodexRateLimits(message.result?.rateLimits);
      if (!limits) {
        return finish(new Error("Codex rate limit response is invalid"));
      }
      finish(null, limits);
    };

    timer = setTimeout(
      () => finish(new Error("Codex rate limit timed out")),
      timeoutMs,
    );

    try {
      // Windowsではcodexが.cmdシムのため、cmd.exe経由で起動する。
      const command = platform === "win32" ? process.env.ComSpec || "cmd.exe" : "codex";
      const args =
        platform === "win32"
          ? ["/d", "/s", "/c", "codex app-server --listen stdio://"]
          : ["app-server", "--listen", "stdio://"];
      child = spawnImpl(command, args, {
        stdio: ["pipe", "pipe", "ignore"],
        windowsHide: true,
      });
    } catch (error) {
      finish(error);
      return;
    }

    child.on("error", (error) => finish(error));
    child.on("exit", () => {
      if (!settled) finish(new Error("Codex app-server exited early"));
    });
    child.stdin.on("error", (error) => finish(error));
    child.stdout.on("data", (chunk) => {
      buffer += chunk.toString();
      let newline;
      while ((newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (!line) continue;
        try {
          handleMessage(JSON.parse(line));
        } catch {
          finish(new Error("Codex app-server returned invalid JSON"));
        }
      }
    });

    send({
      method: "initialize",
      id: 1,
      params: {
        clientInfo: { name: "agent-config-statusline", version: "1.0.0" },
        capabilities: null,
      },
    });
  });
}

async function main() {
  let input = "";
  for await (const chunk of process.stdin) input += chunk;

  let session;
  try {
    session = JSON.parse(input);
  } catch {
    return; // 不正入力ならステータスラインを空にする
  }

  process.stdout.write(await renderStatusline(session));
}

// ANSI 色。閾値に応じて使用率を緑→黄→赤で塗り分ける。
const C = {
  reset: "\x1b[0m",
  dim: "\x1b[2m",
  cyan: "\x1b[36m",
  blue: "\x1b[94m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
};
const sep = `${C.dim} | ${C.reset}`;

function usageColor(p) {
  if (p >= 90) return C.red;
  if (p >= 70) return C.yellow;
  return C.green;
}

const USAGE_BAR_WIDTH = 5;

function usageMeter(p) {
  const v = Math.min(100, Math.max(0, Math.round(p)));
  const used = Math.round((v * USAGE_BAR_WIDTH) / 100);
  const remaining = USAGE_BAR_WIDTH - used;

  return `${usageColor(v)}${v}% ${"▬".repeat(used)}${C.reset}${C.dim}${"▭".repeat(remaining)}${C.reset}`;
}

// total_duration_ms を h/m/s に整形。1時間未満なら時間表示を省く。
function duration(ms) {
  const s = Math.floor((ms || 0) / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${sec}s`;
  return `${sec}s`;
}

function directoryName(dir) {
  return dir.replace(/[\\/]+$/, "").split(/[\\/]/).pop();
}

function isPathWithin(root, target) {
  const relative = path.relative(path.resolve(root), path.resolve(target));
  return (
    relative === "" ||
    (relative !== ".." &&
      !relative.startsWith(`..${path.sep}`) &&
      !path.isAbsolute(relative))
  );
}

function repositoryContext(dir, execFileSyncImpl = execFileSync) {
  const fallback = { name: directoryName(dir), isWorktree: false };

  try {
    const worktrees = execFileSyncImpl(
      "git",
      ["worktree", "list", "--porcelain"],
      {
        cwd: dir,
        stdio: ["ignore", "pipe", "ignore"],
      },
    )
      .toString()
      .split(/\r?\n/)
      .filter((line) => line.startsWith("worktree "))
      .map((line) => line.slice("worktree ".length).trim());

    if (worktrees.length === 0) return fallback;

    let currentIndex = -1;
    let currentPathLength = -1;
    for (const [index, worktree] of worktrees.entries()) {
      if (!isPathWithin(worktree, dir)) continue;
      const pathLength = path.resolve(worktree).length;
      if (pathLength <= currentPathLength) continue;
      currentIndex = index;
      currentPathLength = pathLength;
    }

    if (currentIndex < 0) return fallback;
    return {
      name: directoryName(worktrees[0]),
      isWorktree: currentIndex > 0,
    };
  } catch {
    return fallback;
  }
}

function branch(dir, execFileSyncImpl = execFileSync) {
  try {
    return execFileSyncImpl("git", ["branch", "--show-current"], {
      cwd: dir,
      stdio: ["ignore", "pipe", "ignore"],
    })
      .toString()
      .trim();
  } catch {
    return ""; // git 管理外
  }
}

function isClaudex(model) {
  return /^gpt-5\.6-/.test(model || "");
}

function render(
  d,
  codexLimits = null,
  { execFileSyncImpl = execFileSync } = {},
) {
  const firstLine = [];
  const secondLine = [];

  const model = d.model?.display_name;
  if (model) firstLine.push(`${C.cyan}[${model}]${C.reset}`);

  const dir = d.workspace?.current_dir || d.cwd;
  if (dir) {
    const repository = repositoryContext(dir, execFileSyncImpl);
    const worktreeMarker = repository.isWorktree ? " [WT]" : "";
    firstLine.push(
      `${C.blue}📁 ${repository.name}${worktreeMarker}${C.reset}`,
    );
    const b = branch(dir, execFileSyncImpl);
    if (b) firstLine.push(`🌿 ${b}`);
  }

  // context_window は初回 API 応答前・/compact 直後は欠損する。
  const ctx = d.context_window?.used_percentage;
  if (typeof ctx === "number") secondLine.push(`🧠 ${usageMeter(ctx)}`);

  let five;
  let week;
  if (isClaudex(model)) {
    five = codexLimits?.fiveHour;
    week = codexLimits?.sevenDay;
  } else {
    // rate_limits は Claude.ai (Pro/Max) の初回応答後にのみ現れる。無ければ省く。
    five = d.rate_limits?.five_hour?.used_percentage;
    week = d.rate_limits?.seven_day?.used_percentage;
  }
  if (typeof five === "number") secondLine.push(`5h ${usageMeter(five)}`);
  if (typeof week === "number") secondLine.push(`7d ${usageMeter(week)}`);

  const dur = d.cost?.total_duration_ms;
  if (typeof dur === "number") firstLine.push(`⏱️ ${duration(dur)}`);

  return [firstLine.join(sep), secondLine.join(sep)].filter(Boolean).join("\n");
}

async function renderStatusline(
  session,
  { getCodexRateLimitImpl = getCodexRateLimit } = {},
) {
  const model = session.model?.display_name;
  const codexLimits = isClaudex(model) ? await getCodexRateLimitImpl() : null;
  return render(session, codexLimits);
}

if (require.main === module) {
  main().catch(() => process.exit(0));
}

module.exports = {
  fetchCodexRateLimit,
  getCodexRateLimit,
  render,
  renderStatusline,
  usageMeter,
};
