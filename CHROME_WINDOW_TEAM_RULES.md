# Chrome Window Root Fix Team Rules

## User Goal

Chromeだけがカクつくアニメーションのように移動・変形し、途中の位置やサイズで終了する問題を根本修正する。

## Scope

- 対象はChrome専用ウィンドウ制御だけ。非Chromeはデグレ確認のみ。
- 既存要件を満たすなら、現在の最大16回再送ワークアラウンドに引っ張られない別実装を選んでよい。
- 同じChromeウィンドウへの連続コマンドは古い処理を停止し、最新コマンドだけを完了させる。
- AX readbackが目標frameへ収束したことを確認し、中間frameを成功扱いしない。
- 既存のデバッグ通知・ログ経路を維持する。

## Required Sources

- `AGENTS.md`
- `Sources/Sagasu/AppCoordinator.swift`
- `Sources/Sagasu/WindowManager.swift`
- `Sources/Sagasu/WindowHotKeyMonitor.swift`
- `Tests/SagasuTests/WindowManagerTests.swift`
- `Tests/SagasuTests/ChromeMeetLiveTests.swift`

## Roles

- Manager `p_1489`: scope、統合判断、最終検証、ユーザー報告。
- Implementer: 最小差分の実装と単体テスト。編集可。
- Advisor: read-onlyレビュー。編集禁止。

## Side Effects

- Implementerは指定ソースとテストの編集のみ可。
- 子agentはcommit、push、アプリ起動、kill、install、deploy、外部メッセージ送信をしない。
- Managerだけが検証、ビルド、installed app置換、ライブE2Eを行う。

## Strict Prohibitions

- 非Chromeのframe計算、座標変換、set順序を変更しない。
- 新しい動作定数を根拠なく追加しない。既存仕様・観測・外部一次資料に根拠がなければManagerへ相談する。
- Chromeの途中frameを成功扱いしない。
- ユーザーや他担当の既存差分をreset、checkout、削除しない。
- commit/pushしない。

## Acceptance Criteria

- Chromeの見える多段AX変異とmain-thread同期sleepを除去する。
- 最新コマンドだけが同じウィンドウを収束させ、古い処理が後から上書きしない。
- 成功、期限切れ、キャンセルがログで区別できる。
- 対象テスト、`swift test`、release buildが成功する。
- installed appのChrome移動・変形でカクつきと中間終了が再現しない。

## Reporting

- Implementerは変更ファイル、設計要点、テスト結果、残リスクを`p_1489`へHerdr報告する。
- Advisorは重大度順、ファイル・行番号付きで`p_1489`へHerdr報告する。
- compaction、pane restart、状態不明時はこのファイルを最初に読み直す。
