---
type: dashboard
status: active
created: 2026-06-07
updated: 2026-07-29
---

<!-- agent-config: generated mirror — 正本は agent-config リポジトリ vault/Home.md。再同期: ./scripts/sync-vault-mirror.ps1。Obsidian での直接編集は sync で上書きされます。 -->

# Home

## クイックヘルプ

### トリガー早見表

| 言うこと                                       | 動くスキル                       |
| ---------------------------------------------- | -------------------------------- |
| 「このプロジェクトの状態を確認して」           | `external-memory-reference`      |
| 「これを覚えておいて」「買い物に追加」         | `external-memory-capture`        |
| 「今日はここまで。引き継いで」                 | `external-memory-handoff`        |
| 「今日の計画を作って」                         | `external-memory-daily-plan`     |
| 「Inboxを整理して」                            | `external-memory-inbox`          |
| 「セッションを記録して」「記録漏れを確認して」 | `external-memory-session-digest` |
| 「Vaultのリンク切れを直して」                  | `external-memory-maintenance`    |

詳細な運用規約は [[System/external-memory-rules/index|外部記憶ルール]] を参照。

## 仕様概要

### 全体アーキテクチャ

青=主体（人・AIエージェント・Obsidian）／黄=処理（スキル）／灰=データ（Vault）。

```mermaid
flowchart LR
    Human["人<br/>読む・判断する・依頼する"] --> Agents["AIエージェント"]
    Agents --> Skills["external-memory-* スキル"]
    Skills --> Vault["Obsidian Vault<br/>Markdown正本"]
    Human --> Obsidian["Obsidian<br/>閲覧・編集"]
    Obsidian --> Vault

    classDef actor fill:#e7f0ff,stroke:#4b6bff,color:#111;
    classDef data fill:#f7f7f7,stroke:#888,color:#111;
    classDef process fill:#fff2cc,stroke:#d6a400,color:#111;
    class Human,Agents,Obsidian actor;
    class Vault data;
    class Skills process;
```

### スキルとフォルダ対応

線は各スキルが直接読み書きするフォルダ。スキル間の呼び出しは次の図に分ける。Knowledge / Decisions への後日昇格は、下のデータフローどおり承認後に行う。タスクの正本は文脈ノートか Inbox に置く。System は repo の external-memory-rules のミラーで、maintenance 以外は触らない。

```mermaid
flowchart LR
    subgraph Skills["external-memory-* スキル"]
        Reference["reference<br/>参照"]
        Capture["capture<br/>記録"]
        Handoff["handoff<br/>引き継ぎ"]
        DailyPlan["daily-plan<br/>日次計画"]
        InboxSkill["inbox<br/>Inbox整理"]
        Maintenance["maintenance<br/>Vault横断保守"]
    end

    subgraph Vault["外部記憶 Vault フォルダ"]
        Inbox["Inbox"]
        Daily["Daily"]
        Knowledge["Knowledge"]
        Decisions["Decisions"]
        Handoffs["Handoffs"]
        Projects["Projects"]
        System["System"]
    end

    Archive["Vault外archive<br/>external-memory-archive"]

    Reference --> Projects
    Reference --> Knowledge
    Reference --> Decisions
    Reference --> Handoffs

    Capture --> Inbox
    Capture --> Daily
    Capture --> Projects
    Capture --> Knowledge
    Capture --> Decisions

    Handoff --> Handoffs
    DailyPlan --> Daily
    DailyPlan --> Projects
    InboxSkill --> Inbox
    InboxSkill --> Projects
    InboxSkill --> Knowledge
    InboxSkill --> Decisions
    InboxSkill --> Archive
    Maintenance --> Inbox
    Maintenance --> Daily
    Maintenance --> Projects
    Maintenance --> Knowledge
    Maintenance --> Decisions
    Maintenance --> Handoffs
    Maintenance --> System
    Maintenance --> Archive

    classDef skill fill:#fff2cc,stroke:#d6a400,color:#111;
    classDef folder fill:#f7f7f7,stroke:#888,color:#111;
    class Reference,Capture,Handoff,DailyPlan,InboxSkill,Maintenance skill;
    class Inbox,Daily,Knowledge,Decisions,Handoffs,Projects,System folder;
    classDef external fill:#f7f7f7,stroke:#888,color:#111,stroke-dasharray:4 3;
    class Archive external;
```

### スキルの呼び出し関係

session-digest は作業セッションの外で単独に走り、記録ロジックを capture へ委譲する。handoff は作業セッション内で引き継ぎを書く。maintenance は呼ばれる側で、Vault の保守は自分で行う。実線=必ず通る委譲、点線=条件付きの提案・促し。

```mermaid
flowchart LR
    StartHook["セッション開始hook"] -.->|参照を促す| Reference["reference"]
    Digest["session-digest<br/>単独セッション"] -->|知見・判断の記録| Capture["capture"]
    Digest -.->|構造ゆれが目立てば提案| Maintenance["maintenance"]
    Handoff["handoff<br/>作業の引き継ぎ"] -->|明確な判断・知識| Capture

    classDef skill fill:#fff2cc,stroke:#d6a400,color:#111;
    classDef hook fill:#e7f0ff,stroke:#4b6bff,color:#111;
    class Reference,Capture,Handoff,Digest,Maintenance skill;
    class StartHook hook;
```

### データフロー

黄=承認ゲート。作業中に明確な判断・知見を直接記録する経路は承認不要。Gateを通るのは、既存ノートから後で切り出す昇格・Inbox整理・移動。

```mermaid
flowchart TD
    Raw["作業中の思考・判断・知識・タスク"]
    Inbox["Inbox"]
    Daily["Daily"]
    Projects["Projects"]
    Knowledge["Knowledge"]
    Decisions["Decisions"]
    Archive["Vault外archive"]
    Gate["人の承認"]
    Recall["参照で再利用"]

    Raw -->|迷ったら| Inbox
    Raw -->|日次記録| Daily
    Raw -->|進捗・作業ログ| Projects
    Raw -->|作業中の判断| Decisions
    Raw -->|再利用できる知識| Knowledge

    Inbox -->|inbox整理| Gate
    Daily -.->|後日整理の昇格候補| Gate
    Projects -.->|後日整理の昇格候補| Gate
    Gate -->|昇格| Knowledge
    Gate -->|昇格| Decisions
    Gate -->|移動| Projects
    Gate -->|退避| Archive

    Projects --> Recall
    Knowledge --> Recall
    Decisions --> Recall

    classDef gate fill:#fff2cc,stroke:#d6a400,color:#111;
    class Gate gate;
```
