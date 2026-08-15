---
type: dashboard
status: active
created: 2026-06-07
updated: 2026-08-16
---

<!-- agent-config: generated mirror — 正本は agent-config リポジトリ vault/Home.md。再同期: ./scripts/sync-vault-mirror.ps1。Obsidian での直接編集は sync で上書きされます。 -->

# Home

## クイックヘルプ

### トリガー早見表

| スキル                           | トリガー                                 |
| -------------------------------- | ---------------------------------------- |
| `external-memory-reference`      | セッション開始時の外部記憶の読み込み     |
| `external-memory-capture`        | 作業中の判断・知見の外部記憶への書き込み |
| `external-memory-handoff`        | 「引き継ぎを作成して」                   |
| `external-memory-daily-plan`     | 「今日の計画を作成して」                 |
| `external-memory-inbox`          | 「Inboxを整理して」                      |
| `external-memory-session-digest` | 「外部記憶の記録漏れを補完して」         |
| `external-memory-maintenance`    | 「外部記憶をメンテナンスして」           |

詳細な運用規約は [[System/external-memory-rules/index|外部記憶ルール]] を参照。

## 仕様概要

青=主体・黄=処理・灰=データを示す。

### 全体アーキテクチャ

外部記憶システムはスキルで定義されており、データはMarkdown（Obsidian Vault）。AIによる読み書きと、Obsidianの利用を両立する。

```mermaid
flowchart LR
    Human["人"] --> Agents["AIエージェント<br/>判断・参照・編集"]
    Agents --> Skills["external-memory スキル<br/>外部記憶システム定義"]
    Skills <--> Vault["Obsidian Vault<br/>Markdown正本"]
    Human --> Obsidian["Obsidian<br/>閲覧・編集"]
    Obsidian <--> Vault

    classDef actor fill:#e7f0ff,stroke:#4b6bff,color:#111;
    classDef data fill:#f7f7f7,stroke:#888,color:#111;
    classDef process fill:#fff2cc,stroke:#d6a400,color:#111;
    class Human,Agents,Obsidian actor;
    class Vault data;
    class Skills process;
```

### 外部記憶システムの流れ

作業セッション内での自律的な記憶の更新・参照と、個別依頼による整備に大別される。

```mermaid
flowchart LR
    Human["人"]

    subgraph Session["作業セッション"]
        direction LR
        Work["作業する"] --> RefCap["reference<br/>開始時に前回までを読む<br/><br/>capture<br/>作業中に随時記録する"]
        Hand["handoff<br/>終了時に次へ渡す"]
    end

    Vault[("Obsidian Vault")]

    subgraph Standalone["個別依頼"]
        direction TB
        Plan["daily-plan<br/>今日の計画を立てる"]
        Digest["session-digest<br/>記録漏れを補完する"]
        InboxSkill["inbox<br/>Inboxを振り分ける"]
        Maint["maintenance<br/>構造の乱れを直す"]
    end

    RefCap <--> Vault
    Hand --> Vault

    Human --->|作業依頼| Work
    Human -.->|指示| Hand
    Human -.->|指示| Plan
    Human -.->|指示| Digest
    Human -.->|指示| InboxSkill
    Human -.->|指示| Maint

    Plan --> Vault
    Digest --> Vault
    InboxSkill --> Vault
    Maint --> Vault

    classDef skill fill:#fff2cc,stroke:#d6a400,color:#111;
    classDef data fill:#f7f7f7,stroke:#888,color:#111;
    classDef actor fill:#e7f0ff,stroke:#4b6bff,color:#111;
    class RefCap,Hand,Plan,Digest,InboxSkill,Maint skill;
    class Vault data;
    class Human,Work actor;
```

### スキルと記憶領域の対応

記憶領域は性質ごとにKnowledge・Decisions・Projects等を定義しており、記憶スキルで書き、参照スキルで読む。

```mermaid
flowchart LR
    subgraph Skills["記憶スキル"]
        direction TB
        Cap["capture"]
        Hand["handoff"]
        Plan["daily-plan"]
        InboxSkill["inbox"]
        Maint["maintenance"]
        Digest["session-digest"]
    end

    subgraph VaultF["Obsidian Vault"]
        direction TB
        Inbox["Inbox<br/>人が書く"]
        Core["Projects<br/>概要・状況・TODO<br/><br/>Knowledge<br/>再利用可能な知識<br/><br/>Decisions<br/>重要な判断と理由"]
        Daily["Daily<br/>デイリーノート"]
        Handoffs["Handoffs<br/>セッションの引き継ぎ"]
        System["System<br/>規約のミラー"]
    end

    subgraph RefSkills["参照スキル"]
        Ref["reference"]
    end

    Archive["archive<br/>（Vault外）"]

    Cap -->|判断・知見・進捗| Core
    Digest -->|記録漏れの補完| Core
    Hand -->|引き継ぎ| Handoffs
    Plan -->|今日の計画| Daily
    InboxSkill -->|Inboxからの振り分け| Core
    Maint -->|構造の乱れを修正| VaultF
    VaultF -->|破棄| Archive

    Core --> Ref
    Handoffs --> Ref

    classDef skill fill:#fff2cc,stroke:#d6a400,color:#111;
    classDef folder fill:#f7f7f7,stroke:#888,color:#111;
    classDef actor fill:#e7f0ff,stroke:#4b6bff,color:#111;
    class Cap,Hand,Plan,InboxSkill,Maint,Ref,Digest skill;
    class Inbox,Daily,Core,Handoffs,System folder;
    classDef external fill:#f7f7f7,stroke:#888,color:#111,stroke-dasharray:4 3;
    class Archive external;
```
