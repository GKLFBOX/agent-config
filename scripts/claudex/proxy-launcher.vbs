' claudex: CLIProxyAPI を隠しウィンドウで常駐起動するランチャー。
' Task Scheduler の Interactive 実行でコンソール窓を出さないため、窓を持たない wscript から
' Run(cmd, 0, True) で起動する。0=SW_HIDE で窓を隠し、True で待機してタスクを生かし RestartCount
' 監視を保つ。子の終了コードを WScript.Quit で伝播し、異常終了時にタスク失敗として再起動させる。
' 引数: (0)=CLIProxyAPI 実行ファイルの絶対パス, (1)=config.yaml の絶対パス
Option Explicit
Dim shell, cmd, rc
If WScript.Arguments.Count < 2 Then
    WScript.Quit 2
End If
Set shell = CreateObject("WScript.Shell")
cmd = """" & WScript.Arguments(0) & """ -config """ & WScript.Arguments(1) & """"
rc = shell.Run(cmd, 0, True)
WScript.Quit rc
