# Plugins

## 目的

- Claude Code / Codex CLI で有効化している外部 plugin をホスト別に一覧化する。
- plugin は外部資材であり、このリポジトリでは有効化の参照だけを管理する（本体は各ホストの cache / marketplace から取得）。
- 自作 Codex plugin（`agent-file-backup` 等）は本リポジトリで実体管理するため [codex](../codex/README.md) が扱う。ここには載せない。
- 関連: [claude](../claude/README.md), [codex](../codex/README.md), [skills](../skills/README.md)

## Claude plugins

| プラグイン               | バージョン | マーケットプレイス                                             | 用途                                                                           |
| ------------------------ | ---------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `context-mode`           | 1.0.169    | `context-mode`（`https://github.com/mksglu/context-mode.git`） | 大出力をサンドボックスで処理しコンテキストを節約する。                         |
| `andrej-karpathy-skills` | 1.0.0      | `karpathy-skills`（`forrestchang/andrej-karpathy-skills`）     | コーディング挙動を正すガイドライン skills。                                    |
| `superpowers`            | 6.1.1      | `claude-plugins-official`（Claude Code 公式・内蔵）            | skill 運用基盤（brainstorming / TDD 等のプロセス skill）。                     |
| `obsidian`               | 1.0.1      | `obsidian-skills`（`kepano/obsidian-skills`）                  | Obsidian vault 操作の skills。                                                 |
| `codex`                  | 1.0.5      | `openai-codex`（`openai/codex-plugin-cc`）                     | Codex への調査・設計・レビュー・実装委託。                                     |
| `claude-md-management`   | 1.0.0      | `claude-plugins-official`（Claude Code 公式・内蔵）            | CLAUDE.md の品質監査・学びの取り込み・プロジェクト記憶の更新。                 |
| `security-guidance`      | 2.0.6      | `claude-plugins-official`（Claude Code 公式・内蔵）            | 生成コードのセキュリティレビュー（injection / XSS / SSRF / secret 等の検出）。 |

- plugin 本体は marketplace / plugin cache から取得され、有効化は plugin 単位で管理される。repo 側に source は書かない。
- 各 plugin の有効化設定と SessionStart hook の挙動は [claude](../claude/README.md) を参照。
- バージョンは repo で固定せず plugin cache 側が管理する。上表は `installed_plugins.json`（観測時点 2026-07-24）の現行値で、cache 更新で変動しうる。

## Codex plugins

Codex に外部導入した plugin。Codex 同梱分（`openai-bundled` / `openai-primary-runtime` の documents / spreadsheets / browser / chrome 等）と自作 `agent-file-backup@personal`（[codex](../codex/README.md) で扱う）は除く。

| プラグイン                      | マーケットプレイス / registry                                  | 用途                                                   |
| ------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------ |
| `superpowers@openai-curated`    | `openai-curated`（Codex 公式キュレーション）                   | skill 運用基盤（brainstorming / TDD 等）。             |
| `codex-security@openai-curated` | `openai-curated`（Codex 公式キュレーション）                   | 生成コードのセキュリティレビュー。                     |
| `context-mode@context-mode`     | `context-mode`（`https://github.com/mksglu/context-mode.git`） | 大出力をサンドボックスで処理しコンテキストを節約する。 |

- 有効化の正本は `~/.codex/config.toml` の `[plugins.*]`（`enabled = true`）。バージョンは Codex の plugin cache 側が管理し、config.toml は保持しない。
- Codex 層の配布物・自作 plugin・`config.toml` カタログの詳細は [codex](../codex/README.md)。
- Codex の `defuddle` / Obsidian 系 / `karpathy-guidelines` は plugin ではなく skills CLI 管理の USER skills。導入状況は [codex](../codex/README.md) に記録する。
