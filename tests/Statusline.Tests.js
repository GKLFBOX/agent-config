const test = require("node:test");
const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { PassThrough, Writable } = require("node:stream");
const {
  fetchCodexRateLimit,
  getCodexRateLimit,
  render,
  renderStatusline,
  usageMeter,
} = require("../claude/hooks/statusline.js");

const ANSI = /\x1b\[[0-9;]*m/g;
const plain = (value) => value.replace(ANSI, "");

test("使用率を5セルの短冊で描画する", () => {
  const cases = [
    [0, "0% ▭▭▭▭▭"],
    [42, "42% ▬▬▭▭▭"],
    [49.6, "50% ▬▬▬▭▭"],
    [58, "58% ▬▬▬▭▭"],
    [73, "73% ▬▬▬▬▭"],
    [100, "100% ▬▬▬▬▬"],
    [-1, "0% ▭▭▭▭▭"],
    [101, "100% ▬▬▬▬▬"],
  ];

  for (const [usage, expected] of cases) {
    assert.equal(plain(usageMeter(usage)), expected);
  }
});

test("使用率メーターの色境界を維持する", () => {
  assert.match(usageMeter(69), /^\x1b\[32m69% /);
  assert.match(usageMeter(69.6), /^\x1b\[33m70% /);
  assert.match(usageMeter(70), /^\x1b\[33m70% /);
  assert.match(usageMeter(89), /^\x1b\[33m89% /);
  assert.match(usageMeter(90), /^\x1b\[31m90% /);
  assert.equal(
    usageMeter(42),
    "\x1b[32m42% ▬▬\x1b[0m\x1b[2m▭▭▭\x1b[0m",
  );
});

function fakeGit(worktreeOutput, branchName) {
  return (command, args) => {
    assert.equal(command, "git");
    if (args[0] === "worktree") return Buffer.from(worktreeOutput);
    if (args[0] === "branch") return Buffer.from(`${branchName}\n`);
    throw new Error(`unexpected git command: ${args.join(" ")}`);
  };
}

function cachePath(name) {
  return path.join(os.tmpdir(), `agent-config-statusline-${process.pid}-${name}.json`);
}

function retryPath(cachePath) {
  return `${cachePath}.retry`;
}

function fakeCodexProcess(onRequest) {
  const child = new EventEmitter();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => child.emit("exit", 0);
  child.stdin = new Writable({
    write(chunk, encoding, callback) {
      onRequest(JSON.parse(chunk.toString().trim()), child);
      callback();
    },
  });
  return child;
}

test("Claudeセッションを2行で描画する", () => {
  const output = plain(
    render({
      model: { display_name: "Fable 5" },
      context_window: { used_percentage: 42 },
      rate_limits: {
        five_hour: { used_percentage: 58 },
        seven_day: { used_percentage: 73 },
      },
      cost: { total_duration_ms: 3723000 },
    }),
  );

  assert.equal(
    output,
    "[Fable 5] | ⏱️ 1h 2m\n🧠 42% ▬▬▭▭▭ | 5h 58% ▬▬▬▭▭ | 7d 73% ▬▬▬▬▭",
  );
});

test("main worktreeではrepo名を表示しWTを付けない", () => {
  const execFileSyncImpl = fakeGit(
    "worktree X:/fixtures/agent-config\n\n",
    "main",
  );

  const output = plain(
    render(
      {
        workspace: { current_dir: "X:/fixtures/agent-config" },
      },
      null,
      { execFileSyncImpl },
    ),
  );

  assert.equal(output, "📁 agent-config | 🌿 main");
});

test("linked worktreeでは元repo名とWTを表示する", () => {
  const execFileSyncImpl = fakeGit(
    [
      "worktree <repo-root>",
      "",
      "worktree <repo-root>/.claude/worktrees/fix-run-claude-env-isolation",
      "",
    ].join("\n"),
    "worktree-fix-run-claude-env-isolation",
  );

  const output = plain(
    render(
      {
        cwd: "<repo-root>",
        workspace: {
          current_dir:
            "<repo-root>/.claude/worktrees/fix-run-claude-env-isolation/src",
        },
      },
      null,
      { execFileSyncImpl },
    ),
  );

  assert.equal(
    output,
    "📁 agent-config [WT] | 🌿 worktree-fix-run-claude-env-isolation",
  );
});

test("Git管理外ではディレクトリ名へフォールバックする", () => {
  const execFileSyncImpl = () => {
    throw new Error("not a git repository");
  };

  const output = plain(
    render(
      {
        model: { display_name: "Fable 5" },
        workspace: { current_dir: "E:/scratch" },
        context_window: { used_percentage: 42 },
      },
      null,
      { execFileSyncImpl },
    ),
  );

  assert.equal(
    output,
    "[Fable 5] | 📁 scratch\n🧠 42% ▬▬▭▭▭",
  );
});

test("initialize後に5時間・7日間使用率を期間で分類する", async () => {
  const methods = [];
  const spawnImpl = () =>
    fakeCodexProcess((request, child) => {
      methods.push(request.method);
      if (request.id === 1) {
        queueMicrotask(() =>
          child.stdout.write(`${JSON.stringify({ id: 1, result: {} })}\n`),
        );
      }
      if (request.id === 2) {
        queueMicrotask(() =>
          child.stdout.write(
            `${JSON.stringify({
              id: 2,
              result: {
                rateLimits: {
                  primary: {
                    usedPercent: 34,
                    windowDurationMins: 10080,
                    resetsAt: 1785525776,
                  },
                  secondary: {
                    usedPercent: 21,
                    windowDurationMins: 300,
                    resetsAt: 1785525776,
                  },
                },
              },
            })}\n`,
          ),
        );
      }
    });

  const limits = await fetchCodexRateLimit({ spawnImpl, timeoutMs: 100 });

  assert.deepEqual(methods, ["initialize", "account/rateLimits/read"]);
  assert.deepEqual(limits, { fiveHour: 21, sevenDay: 34 });
});

test("7日間枠だけのCodex応答を取得する", async () => {
  const spawnImpl = () =>
    fakeCodexProcess((request, child) => {
      const result =
        request.id === 1
          ? {}
          : {
              rateLimits: {
                primary: { usedPercent: 21, windowDurationMins: 10080 },
                secondary: null,
              },
            };
      queueMicrotask(() =>
        child.stdout.write(`${JSON.stringify({ id: request.id, result })}\n`),
      );
    });

  assert.deepEqual(await fetchCodexRateLimit({ spawnImpl, timeoutMs: 100 }), {
    sevenDay: 21,
  });
});

test("WindowsではCodexをcmd.exe経由で起動する", async () => {
  let invocation;
  const spawnImpl = (command, args) => {
    invocation = { command, args };
    return fakeCodexProcess((request, child) => {
      const result =
        request.id === 1
          ? {}
          : {
              rateLimits: {
                primary: { usedPercent: 21, windowDurationMins: 10080 },
              },
            };
      queueMicrotask(() =>
        child.stdout.write(`${JSON.stringify({ id: request.id, result })}\n`),
      );
    });
  };

  await fetchCodexRateLimit({ spawnImpl, platform: "win32", timeoutMs: 100 });

  assert.equal(invocation.command, process.env.ComSpec || "cmd.exe");
  assert.deepEqual(invocation.args, [
    "/d",
    "/s",
    "/c",
    "codex app-server --listen stdio://",
  ]);
});

test("7日間枠の形式が不正なら失敗する", async () => {
  const spawnImpl = () =>
    fakeCodexProcess((request, child) => {
      const result = request.id === 1 ? {} : { rateLimits: { primary: null } };
      queueMicrotask(() =>
        child.stdout.write(`${JSON.stringify({ id: request.id, result })}\n`),
      );
    });

  await assert.rejects(
    fetchCodexRateLimit({ spawnImpl }),
    /response is invalid/,
  );
});

test("Codex取得時に範囲外の使用率を拒否する", async () => {
  const spawnImpl = () =>
    fakeCodexProcess((request, child) => {
      const result =
        request.id === 1
          ? {}
          : {
              rateLimits: {
                primary: { usedPercent: 101, windowDurationMins: 10080 },
              },
            };
      queueMicrotask(() =>
        child.stdout.write(`${JSON.stringify({ id: request.id, result })}\n`),
      );
    });

  await assert.rejects(
    fetchCodexRateLimit({ spawnImpl }),
    /response is invalid/,
  );
});

test("不正なCodex枠を無視して有効な枠を取得する", async () => {
  const spawnImpl = () =>
    fakeCodexProcess((request, child) => {
      const result =
        request.id === 1
          ? {}
          : {
              rateLimits: {
                primary: { usedPercent: 101, windowDurationMins: 300 },
                secondary: { usedPercent: 34, windowDurationMins: 10080 },
              },
            };
      queueMicrotask(() =>
        child.stdout.write(`${JSON.stringify({ id: request.id, result })}\n`),
      );
    });

  assert.deepEqual(await fetchCodexRateLimit({ spawnImpl, timeoutMs: 100 }), {
    sevenDay: 34,
  });
});

test("応答がなければタイムアウトする", { timeout: 100 }, async () => {
  const spawnImpl = () => fakeCodexProcess(() => {});
  await assert.rejects(
    fetchCodexRateLimit({ spawnImpl, timeoutMs: 10 }),
    /timed out/,
  );
});

test("5分以内のキャッシュではCodexを起動しない", async () => {
  const file = cachePath("fresh");
  fs.writeFileSync(
    file,
    JSON.stringify({
      fiveHour: 12,
      sevenDay: 21,
      fetchedAt: 1_000_000,
      attemptedAt: 1_000_000,
    }),
  );
  let calls = 0;

  const result = await getCodexRateLimit({
    cachePath: file,
    now: 1_000_000 + 299_999,
    fetchImpl: async () => {
      calls += 1;
      return { usedPercent: 99, windowDurationMins: 10080 };
    },
  });

  assert.equal(calls, 0);
  assert.deepEqual(result, { fiveHour: 12, sevenDay: 21 });
});

test("取得成功時は許可した値だけを保存する", async () => {
  const file = cachePath("success");
  const result = await getCodexRateLimit({
    cachePath: file,
    now: 2_000_000,
    fetchImpl: async () => ({
      fiveHour: 23,
      sevenDay: 34,
      accessToken: "must-not-be-written",
    }),
  });
  const stored = fs.readFileSync(file, "utf8");

  assert.deepEqual(result, { fiveHour: 23, sevenDay: 34 });
  assert.deepEqual(JSON.parse(stored), {
    fiveHour: 23,
    sevenDay: 34,
    fetchedAt: 2_000_000,
    attemptedAt: 2_000_000,
  });
  assert.doesNotMatch(stored, /must-not-be-written/);
});

test("旧形式キャッシュは再取得して置き換える", async () => {
  const file = cachePath("legacy");
  fs.writeFileSync(
    file,
    JSON.stringify({
      usedPercent: 21,
      windowDurationMins: 10080,
      fetchedAt: 2_500_000,
      attemptedAt: 2_500_000,
    }),
  );
  let calls = 0;

  const result = await getCodexRateLimit({
    cachePath: file,
    now: 2_500_001,
    fetchImpl: async () => {
      calls += 1;
      return { sevenDay: 22 };
    },
  });

  assert.equal(calls, 1);
  assert.deepEqual(result, { sevenDay: 22 });
  assert.deepEqual(JSON.parse(fs.readFileSync(file, "utf8")), {
    sevenDay: 22,
    fetchedAt: 2_500_001,
    attemptedAt: 2_500_001,
  });
});

test("失敗後60秒間は再試行しない", async () => {
  const file = cachePath("retry");
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
    throw new Error("offline");
  };

  assert.equal(
    await getCodexRateLimit({ cachePath: file, now: 3_000_000, fetchImpl }),
    null,
  );
  assert.equal(
    await getCodexRateLimit({ cachePath: file, now: 3_059_999, fetchImpl }),
    null,
  );
  assert.equal(calls, 1);
  assert.deepEqual(JSON.parse(fs.readFileSync(retryPath(file), "utf8")), {
    attemptedAt: 3_000_000,
  });
});

test("失敗記録は並行取得の成功キャッシュを上書きしない", async () => {
  const file = cachePath("race");
  const success = {
    fiveHour: 22,
    sevenDay: 44,
    fetchedAt: 4_000_000,
    attemptedAt: 4_000_000,
  };

  const result = await getCodexRateLimit({
    cachePath: file,
    now: 4_000_000,
    fetchImpl: async () => {
      fs.writeFileSync(file, JSON.stringify(success));
      throw new Error("concurrent request failed");
    },
  });

  assert.equal(result, null);
  assert.deepEqual(JSON.parse(fs.readFileSync(file, "utf8")), success);
  assert.deepEqual(JSON.parse(fs.readFileSync(retryPath(file), "utf8")), {
    attemptedAt: 4_000_000,
  });
});

test("未来の成功時刻をfresh cacheとして使わない", async () => {
  const file = cachePath("future-success");
  fs.writeFileSync(
    file,
    JSON.stringify({
      sevenDay: 21,
      fetchedAt: 5_000_001,
      attemptedAt: 5_000_001,
    }),
  );
  let calls = 0;

  const result = await getCodexRateLimit({
    cachePath: file,
    now: 5_000_000,
    fetchImpl: async () => {
      calls += 1;
      return { sevenDay: 22 };
    },
  });

  assert.equal(calls, 1);
  assert.deepEqual(result, { sevenDay: 22 });
});

test("未来の失敗時刻で再試行を抑止しない", async () => {
  const file = cachePath("future-retry");
  fs.writeFileSync(retryPath(file), JSON.stringify({ attemptedAt: 6_000_001 }));
  let calls = 0;

  const result = await getCodexRateLimit({
    cachePath: file,
    now: 6_000_000,
    fetchImpl: async () => {
      calls += 1;
      return { sevenDay: 23 };
    },
  });

  assert.equal(calls, 1);
  assert.deepEqual(result, { sevenDay: 23 });
});

test("claudexはCodexの5hと7dを表示する", async () => {
  const output = plain(
    await renderStatusline(
      {
        model: { display_name: "gpt-5.6-sol" },
        context_window: { used_percentage: 42 },
        rate_limits: {
          five_hour: { used_percentage: 99 },
          seven_day: { used_percentage: 99 },
        },
      },
      {
        getCodexRateLimitImpl: async () => ({
          fiveHour: 21,
          sevenDay: 34,
        }),
      },
    ),
  );

  assert.equal(
    output,
    "[gpt-5.6-sol]\n🧠 42% ▬▬▭▭▭ | 5h 21% ▬▭▭▭▭ | 7d 34% ▬▬▭▭▭",
  );
});

test("claudexは欠損した5hを省いてCodexの7dを表示する", async () => {
  const output = plain(
    await renderStatusline(
      {
        model: { display_name: "gpt-5.6-sol" },
        context_window: { used_percentage: 42 },
        rate_limits: {
          five_hour: { used_percentage: 99 },
          seven_day: { used_percentage: 99 },
        },
      },
      {
        getCodexRateLimitImpl: async () => ({ sevenDay: 21 }),
      },
    ),
  );

  assert.equal(output, "[gpt-5.6-sol]\n🧠 42% ▬▬▭▭▭ | 7d 21% ▬▭▭▭▭");
});

test("Codex取得失敗時もclaudexの他の表示を維持する", async () => {
  const output = plain(
    await renderStatusline(
      {
        model: { display_name: "gpt-5.6-sol" },
        context_window: { used_percentage: 42 },
      },
      { getCodexRateLimitImpl: async () => null },
    ),
  );

  assert.equal(output, "[gpt-5.6-sol]\n🧠 42% ▬▬▭▭▭");
});

test("stdin.write例外時にCodexプロセスを終了する", async () => {
  let kills = 0;
  const child = new EventEmitter();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.stdin = new EventEmitter();
  child.stdin.write = () => {
    throw new Error("stdin closed");
  };
  child.kill = () => {
    kills += 1;
    child.emit("exit", 0);
  };

  await assert.rejects(
    fetchCodexRateLimit({ spawnImpl: () => child, timeoutMs: 100 }),
    /stdin closed/,
  );
  assert.equal(kills, 1);
});

test("stdinのEPIPEを即時エラーとして処理する", { timeout: 100 }, async () => {
  const child = new EventEmitter();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.stdin = new EventEmitter();
  child.stdin.write = () => {
    queueMicrotask(() => child.stdin.emit("error", new Error("EPIPE")));
  };
  child.kill = () => child.emit("exit", 0);

  await assert.rejects(
    fetchCodexRateLimit({ spawnImpl: () => child, timeoutMs: 50 }),
    /EPIPE/,
  );
});
