---
name: external-memory-session-digest
description: 作業セッションの記録漏れを、transcriptを読む単独セッションで回収したいときに使用する。セッション直後でも、その日の作業を終えてからまとめてでもよい。
---

# External Memory: Session Digest

規約は正本に従う: `../external-memory-rules/core.md`。記録の実務は`external-memory-capture`へ委譲し、本スキルは抽出と突き合わせを持つ。

作業セッションの末尾では実行しない。単独セッションとして起動する。読み込んだtranscriptが作業セッションの先頭に居座り、以後の全ターンで運ばれるためである。

1. 対象Projectノートを特定する（repo 連動なら repo 名、それ以外は日本語名）。frontmatterのUTC時刻`digested`を読む。
2. `digested`がなければdigest未実施として扱い、対象範囲をユーザーへ確認する。
3. transcriptをMarkdownへ変換する。

   ```
   PYTHONIOENCODING=utf-8 claude-code-log <project-dir> --format md --detail minimal \
     --compact --from-date <digested-utc> --no-individual-sessions -o <出力先>
   ```

   `<project-dir>`は`~/.claude/projects/<パスをハイフンへ置換した名前>`。`--session-id`はキャッシュ未構築だと引けないため、ディレクトリかJSONLの絶対パスを渡す。

   `claude-code-log`は`--from-date`のオフセットを解釈しない。transcriptのUTC時刻と直接比較するため、`digested`をUTCのオフセットなし形式で渡す。`digested`がない初回は、確認した開始時刻をUTCへ変換して`<digested-utc>`とする。

4. `git log --since=<digested-utc>Z --stat`で同期間のコミットを取得する。`Z`を付け、`digested`と同じ瞬間をUTCとして指定する。`--detail minimal`はツール操作を残さないため、実行した作業はコミット履歴から取る。

   `--since`へ時刻なしの日付を渡さない。git は欠けた時刻を現在時刻で補完するため、当日のコミットを黙って落とす。初回も、確認した開始時刻をUTCへ変換して時刻まで書く。

5. 変換結果とコミット履歴を突き合わせ、知見、判断、完了したTodo、新規のTodoを抽出する。
6. 明確な知見と判断を`external-memory-capture`でKnowledge / Decision へ保存する。保存前に既存ノートを検索し、同じ内容を二重に作らない。`## 関連`へ対象Projectノートの`[[wikilink]]`を置く。
7. Projectノートを更新する。現在の状態を5文以内の散文で置換し、作業ログへ1行追記し（直近10件を超える古い行は削除）、Todoの完了分を削除して新規を追記する。
8. `digested`を、処理した最後のセッションの終了時刻をUTCへ変換した`YYYY-MM-DDThh:mm`形式で進める。タイムゾーン接尾辞は付けない。`updated`も当日に更新する。
9. Vaultの構造ゆれが目立つ場合は`external-memory-maintenance`を提案する。
10. 保存内容と、次に着手できる作業を報告する。

## 対象外

ネイティブの`codex` CLIのセッションは`~/.claude/projects`の外にあり、変換できない。claudex経由でCodexを使ったセッションは対象になる。

transcriptの保持期間は約30日で、それを超えたセッションは変換できない。追わない。
