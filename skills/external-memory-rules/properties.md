---
type: system
status: active
created: 2026-06-30
updated: 2026-07-29
---

# 外部記憶ルール — Properties

frontmatterは絞り込み用の索引とする。人が読む情報は本文へ置く。

共通Properties:

```yaml
---
type: project
status: active
created: 2026-06-07
updated: 2026-06-07
---
```

ノート種別ごとの`status`許容値と追加Properties:

| 種別      | 置き場所        | `status`許容値            | 追加Properties                     |
| --------- | --------------- | ------------------------- | ---------------------------------- |
| Project   | `Projects`      | `active` / `planned`      | `repo`, `digested`                 |
| Knowledge | `Knowledge`     | `active` / `idea`         | `topics`, `source`                 |
| Decision  | `Decisions`     | `accepted` / `superseded` | `project`, `decided`, `supersedes` |
| Handoff   | `Handoffs`      | `active`                  | `project`, `work`, `next`          |
| Capture   | `Inbox`         | `open`                    | なし                               |
| System    | `System`        | `active`                  | なし                               |
| Dashboard | ルート`Home.md` | `active`                  | なし                               |
| Daily     | `Daily`         | 持たない                  | なし                               |

Dailyは`type`、`created`、`updated`だけを持つ。日付の正本はファイル名とし、frontmatterへ再掲しない。

`project` と `repo` はProjectノート名の素の文字列で書く。wikilink（`[[名前]]`）や引用符で囲まない。書式が揺れると `external-memory-reference` の property 絞り込みと `external-memory-maintenance` の照合が一致しなくなる。

`digested`は`external-memory-session-digest`が処理を終えたtranscriptの位置を指す。UTCの`YYYY-MM-DDThh:mm`形式で時刻まで持ち、`Z`などのタイムゾーン接尾辞を持たない。`claude-code-log --from-date`がオフセットを解釈せず、transcriptのUTC時刻と直接比較するためである。同じ日に複数回digestを走らせるため、日付粒度では処理済みの位置を表せない。表示するときだけローカル時刻へ変換する。

Knowledgeの`source`は次の4値から選ぶ。出典URL、検証環境、実施日は本文`## 詳細`へ書く。

- `local-investigation`：手元の環境やリポジトリを調べて得た
- `web-research`：公開ドキュメントや記事を読んで得た
- `session`：作業中のやり取りから得た
- `hands-on`：実機を動かして確かめた

Decisionの `supersedes` で参照されたノートは `status: superseded` にする。参照した側と参照された側で状態が食い違うと、どちらが現行の判断か辿れなくなる。

ノートを編集した場合は `updated` を当日に更新する。ただしスキーマの機械的移行では更新しない。`updated` が「最後に中身を触った日」を指す信号を保つためである。

`System/external-memory-rules/_GENERATED.md` は生成マーカーのためfrontmatterを持たない。
