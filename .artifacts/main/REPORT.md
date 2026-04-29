# main / launcher-v1

作成日: 2026-04-27
ブランチ: main
状態: レビュー待ち

## 📌 今回の確認項目

**今回確認してほしい点**

| # | Item | Question/Note |
|---|------|---------------|
| 1 | Notes.app 連携 | 初回は Apple Events 権限が必要です。この権限要求の前提でよいか確認してください。 |
| 2 | file 検索スコープ | Desktop / Downloads / Documents / Pictures / Movies / Recent Places / Dropbox / iCloud Drive に絞っています。広げるべき場所があれば指定してください。 |
| 3 | クリップボード結果の動作 | `v ` の結果選択時は「その内容を現在のクリップボードへ戻す」動作です。自動 paste まで必要なら次で追加します。 |

---

## 🔄 修正依頼と対処

| # | User Request (原文) | Response (対処内容) | 検証方法 |
|---|---------------------|---------------------|----------|
| 1 | 「raycastのクリップボード検索がイケてないので作り直します。そして、raycast自体のアプリケーションランチャー部分も作り直します。option + spaceがデフォルトです。アプリケーション検索＋ファイル検索＋notes.app検索 + クリップボード履歴保存・検索をまず作成してください。option + space -> デフォルトでアプリケーション優先検索です。`f ` と打つとfile検索、`n `でnotes検索、`v `でクリップボード検索です。file検索は基本的にdesktop, downloads, 最近ユーザーが開いた場所、書類、写真、動画、あればdropbox、icloud driveの場所程度に限定して速度を上げます。」 | SwiftUI/AppKit の macOS ネイティブアプリを新規作成し、Option+Space のグローバルホットキー、アプリ優先のデフォルト検索、`f `/`n `/`v ` のモード切替、`mdfind` ベースの限定ファイル検索、AppleScript ベースの Notes 検索、JSON 永続化つきクリップボード履歴を実装しました。主要ファイルは `Sources/Sagasu/` 以下です。 | `swift test`、`CGWindowList` による `windowCount=1`、`~/Library/Application Support/Sagasu/clipboard-history.json` 更新、Notes 権限不足時のエラー露出を `verification.log` に保存。 |
| 2 | 「いえ、起動しないです。どこで起動しているの？また検索バーはraycastみたいに出るの？」「はい、じゃあ直してください。！」 | ランチャー生成を `applicationDidFinishLaunching` 直後ではなく次の runloop tick に遅延し、無効な `collectionBehavior` の組み合わせを除去し、ウィンドウの自動即時クローズを止めました。これで起動直後に消えていたウィンドウが残る形に修正しました。 | `swift test` と `.artifacts/main/verification-launch-fix.log` のウィンドウダンプで、Sagasu の 816x628 ウィンドウが起動後も残っていることを確認。 |
| 3 | 「- option + spaceで起動したのに、input formにキーが当たらない。activeになったら常に当たる必要がある。なんなら、他の項目を↑↓で選択中だとしても、input formはキーボード入力を受け付ける必要がある。 また、サイズが大きいので、もうちょっと小さくして。フォントも微妙です。ゴシック系にして。」「明示的にフォーカスが外れたらすぐ消して。ESCでも一瞬で消えて。消える時にフェードしないで。」 | 検索入力欄を SwiftUI の `TextField` から AppKit の `NSTextField` ラッパーに切り替え、常に first responder を維持しつつ ↑↓ で候補選択できるようにしました。加えてウィンドウを 680x460 ベースへ縮小し、rounded font をやめて標準サンセリフ系へ変更し、フォーカス外れ / ESC で即時に非表示、フェードなしの挙動へ修正しました。 | `swift test` と `.artifacts/main/verification-input-ui.log` で、起動後のウィンドウサイズ縮小と ESC 後の `count=0` を記録。 |
| 4 | 「上下カーソルとctrl + npで上下のカード移動させるようにしてってことね。」 | `NSTextField` の field editor command routing を使うように変更し、↑↓ と Ctrl+N / Ctrl+P はカード移動、左右キーは入力欄内カーソル移動のままにしました。 | `swift test` |
| 5 | 「ううん、移動できないよ。」「はい、やりきって。やったら毎回再起動して」 | キー処理を field editor delegate 依存から `NSWindow.sendEvent(_:)` ベースへ切り替え、↑↓ と Ctrl+N / Ctrl+P をウィンドウレベルで先にカード移動へルーティングするようにしました。修正後に毎回再起動する要求に合わせて Sagasu を再起動済みです。 | `swift test`、再起動後の `count=1` と Accessibility `1` を確認。 |
| 6 | 「もうちょっと縦方向にたいして短くコンパクトになりませんか。数行ですでにUIが埋め尽くされているので、縦方向の高さをそれぞれの項目で減らして情報密度を上げてください。」 | ヘッダー余白、カード上下余白、行間、空状態余白、全体高さを一段ずつ削って、縦方向の情報密度を上げました。 | `swift test`、`.artifacts/main/verification-density.log`、再起動後の on-screen ウィンドウ `Height = 448` を確認。 |
| 7 | 「f png として、大量にあるはずの画像が出てきません。 また画像がある場合は、そのサムネも行の左に出す必要があります。」 | file 検索を `-name` 依存から Spotlight の metadata predicate ベースへ切り替え、ファイル名・表示名・拡張子・`public.png` の content type まで検索対象に広げました。表示側ではアプリは実アイコン、画像ファイルは実サムネイル、その他ファイルはファイルアイコンを左に出すように変更しました。 | `swift test`、`.artifacts/main/verification-image-search.log` の PNG クエリ結果サンプル 20 件、再起動後の on-screen ウィンドウ `count=1` を確認。 |
| 8 | 「今はまだ出ないね。」 | `FileSearchService` に Spotlight 取りこぼし時の filesystem fallback を追加し、あわせて `SearchEngine` の Swift 6 concurrency build error を修正して再ビルド・再起動しました。今回の起動プロセスは PID `14721` で立ち上がっています。 | `swift test`、`.artifacts/main/verification-restart-build.log` の再ビルド成功ログ、`ps -p 14721` の起動確認。 |
| 9 | 「ずっとこれ。どうすればいい？」 | 原因は `mdfind` のヒット数が多いと `ShellCommandRunner` が pipe 出力を読み切る前に `waitUntilExit()` で詰まり、結果反映まで進まないことでした。stdout/stderr を実行中に継続読取するよう修正し、加えて検索中は `Searching…` を出し、0 件時は query あり/なしで空状態文言を分けました。修正後に回帰テストを追加し、Sagasu を再起動しました。 | `swift test`、追加した `shellCommandRunnerHandlesLargeOutput()`、`.artifacts/main/verification-file-search-hang-fix.log`、再起動後の `ps -p 19630`。 |
| 10 | 「ここに更にchromeでの検索導線を追加したいのですが、どうすればいい？」「ChatGPTに対しての導線も作成できる？」「未着は全部やって。」 | デフォルトの application モードで query を入力したとき、上位 3 件のアプリ結果の直後に `Search Google in Chrome` と `Ask ChatGPT in Chrome` の 2 アクションを差し込みました。Chrome が入っていれば Chrome を優先起動し、未導入なら既定ブラウザへフォールバックします。対応ファイルは `Sources/Sagasu/WebRouteSearchService.swift`、`SearchEngine.swift`、`AppCoordinator.swift`、`SearchViewModel.swift`、`SearchMode.swift` です。 | `swift test`、追加した `webRoutesAreEmptyForBlankQuery()` / `webRoutesIncludeGoogleAndChatGPT()`、`.artifacts/main/verification-web-routes.log`、再起動後の `ps -p 57235`。 |
| 11 | 「クリップボードですが、デフォルト3ヶ月。一度でも再利用されたらそれだけ半年延長ルール。そして、選んだ状態で⌘Pが押されたらピン留め(無期限)昇格トグルになるようんして。画像もクリップボードに保持する、を追加して。」 | `ClipboardHistoryStore.swift` を刷新し、保持期限を「既定 3 か月 / 再利用で 6 か月延長 / pinned は無期限」に変更しました。`SearchResult` の clipboard action は entry ID ベースに変更し、`⌘P` で選択中 clipboard entry の pin toggle を走らせる配線を `LauncherPanelController.swift` / `SearchInputField.swift` / `SearchViewModel.swift` / `AppCoordinator.swift` に追加しました。さらに画像 clipboard を PNG として `~/Library/Application Support/Sagasu/clipboard-images/` に保存し、`v ` 検索でサムネイル表示・復元できるようにしました。 | `swift test`、追加した `ClipboardEntryTests.swift` の 3 テスト、`.artifacts/main/verification-clipboard-rules.log` の text/image 永続化ログ、再起動後の `ps -p 35832`。 |
| 12 | 「画像ですが、今のサムネだと小さいので、画像の場合だけ右に拡大サムネ出して。 また、画像だけ検索したい場合があるので、viとしたらクリップボードかつ画像だけの検索にして」 | `ParsedSearchQuery` に clipboard image-only flag を追加し、`vi` / `vi <query>` を clipboard image-only search に割り当てました。検索 UI は選択中 result が画像のときだけ右側に拡大プレビュー pane を出すようにし、`v ` は text+image、`vi ` は image-only で使い分けられるようにしました。対応ファイルは `SearchMode.swift`、`SearchViewModel.swift`、`SearchEngine.swift`、`ClipboardHistoryStore.swift`、`SearchRootView.swift` です。 | `swift test`、追加した `parsesClipboardImagePrefix()`、`.artifacts/main/verification-clipboard-image-preview.log`、再起動後の `ps -p 73578`。 |

---

## 📋 累積フィードバック履歴

<details open>
<summary><strong>Latest: 2026-04-27</strong></summary>

| フィードバック | 状態 | 対処内容 |
|--------------|------|----------|
| 「raycastのクリップボード検索がイケてないので作り直します。そして、raycast自体のアプリケーションランチャー部分も作り直します。option + spaceがデフォルトです。アプリケーション検索＋ファイル検索＋notes.app検索 + クリップボード履歴保存・検索をまず作成してください。option + space -> デフォルトでアプリケーション優先検索です。`f ` と打つとfile検索、`n `でnotes検索、`v `でクリップボード検索です。file検索は基本的にdesktop, downloads, 最近ユーザーが開いた場所、書類、写真、動画、あればdropbox、icloud driveの場所程度に限定して速度を上げます。」 | ✅ 実装済み | SwiftUI/AppKit + Carbon で新規ランチャーを作成し、アプリ優先検索、prefix 切替、限定スコープ file 検索、Notes 検索、クリップボード履歴保存・検索を実装しました。 |
| 「いえ、起動しないです。どこで起動しているの？また検索バーはraycastみたいに出るの？」「はい、じゃあ直してください。！」 | ✅ 対処済み | ウィンドウ生成タイミングと AppKit collection behavior を見直し、起動直後に消える挙動を止めました。 |
| 「- option + spaceで起動したのに、input formにキーが当たらない。activeになったら常に当たる必要がある。なんなら、他の項目を↑↓で選択中だとしても、input formはキーボード入力を受け付ける必要がある。 また、サイズが大きいので、もうちょっと小さくして。フォントも微妙です。ゴシック系にして。」「明示的にフォーカスが外れたらすぐ消して。ESCでも一瞬で消えて。消える時にフェードしないで。」 | ✅ 対処済み | AppKit 入力欄へ差し替えて常時入力を優先し、サイズとタイポグラフィを調整し、即時 hide 挙動へ変更しました。 |
| 「上下カーソルとctrl + npで上下のカード移動させるようにしてってことね。」 | ✅ 対処済み | field editor の command selector を拾う形に変更し、上下カード移動へ流すようにしました。 |
| 「ううん、移動できないよ。」「はい、やりきって。やったら毎回再起動して」 | ✅ 対処済み | ウィンドウレベルのキーイベント処理へ切り替え、修正後に Sagasu を再起動しました。 |
| 「もうちょっと縦方向にたいして短くコンパクトになりませんか。数行ですでにUIが埋め尽くされているので、縦方向の高さをそれぞれの項目で減らして情報密度を上げてください。」 | ✅ 対処済み | ヘッダーとカードの縦余白、テキストサイズ、全体高さを圧縮し、再起動しました。 |
| 「f png として、大量にあるはずの画像が出てきません。 また画像がある場合は、そのサムネも行の左に出す必要があります。」 | ✅ 対処済み | Spotlight metadata query を強化し、画像結果にはサムネイル、アプリには実アイコン、その他ファイルにはファイルアイコンを表示するようにしました。 |
| 「今はまだ出ないね。」 | 🔄 再修正済み | filesystem fallback を追加し、`SearchEngine` のビルドエラーを直してから Sagasu を再起動しました。 |
| 「ずっとこれ。どうすればいい？」 | 🔄 再修正済み | `ShellCommandRunner` の大量出力ハングを直し、検索中表示と query あり/なしの空状態文言を分けて、Sagasu を再起動しました。 |
| 「ここに更にchromeでの検索導線を追加したいのですが、どうすればいい？」「ChatGPTに対しての導線も作成できる？」「未着は全部やって。」 | ✅ 対処済み | デフォルト検索に Google / ChatGPT 導線を追加し、Chrome 優先起動 + 既定ブラウザフォールバックにしました。 |
| 「クリップボードですが、デフォルト3ヶ月。一度でも再利用されたらそれだけ半年延長ルール。そして、選んだ状態で⌘Pが押されたらピン留め(無期限)昇格トグルになるようんして。画像もクリップボードに保持する、を追加して。」 | ✅ 対処済み | 3 か月/6 か月/pin ルール、⌘P pin toggle、画像 clipboard の保存・検索・復元を追加しました。 |
| 「画像ですが、今のサムネだと小さいので、画像の場合だけ右に拡大サムネ出して。 また、画像だけ検索したい場合があるので、viとしたらクリップボードかつ画像だけの検索にして」 | ✅ 対処済み | 画像選択時の右側拡大プレビューと、`vi` の image-only clipboard 検索を追加しました。 |

</details>

---

## 背景
- Raycast 代替の最初の動く版を空リポジトリから新規に作成。
- macOS ネイティブ動作を優先して SwiftUI/AppKit + Carbon を採用。
- Notes 検索は Notes.app scripting に依存するため、ユーザー環境の Automation 権限が前提。

## Todo
- [ ] Option+Space ランチャー基盤（実装済み・承認待ち）
- [ ] アプリ優先検索と prefix 切替（実装済み・承認待ち）
- [ ] 限定スコープ file 検索（実装済み・承認待ち）
- [ ] Notes.app 検索（実装済み・権限確認待ち）
- [ ] クリップボード履歴保存・検索（実装済み・承認待ち）

## 証跡

### 生成物

| 生成物 | 説明 |
|--------|------|
| [verification.log](./verification.log) | `swift test` 成功、ランチャー起動後の `windowCount=1`、クリップボード永続化 JSON 更新、Notes 権限制約のログを保存。 |
| [verification-launch-fix.log](./verification-launch-fix.log) | 起動不具合修正後のプロセス・ウィンドウダンプ。 |
| [verification-input-ui.log](./verification-input-ui.log) | 入力欄/UI 調整後のウィンドウサイズと ESC hide 記録。 |
| [verification-density.log](./verification-density.log) | 縦密度調整後のウィンドウサイズ記録。 |
| [verification-image-search.log](./verification-image-search.log) | 画像検索強化後の PNG 結果サンプルと起動中ウィンドウ記録。 |
| [verification-restart-build.log](./verification-restart-build.log) | Swift 6 concurrency 修正後の再ビルド成功ログと、再起動した Sagasu プロセス PID `14721` の記録。 |
| [verification-file-search-hang-fix.log](./verification-file-search-hang-fix.log) | 大量 stdout を返す回帰テスト `shellCommandRunnerHandlesLargeOutput()` を含む `swift test` 成功ログと、再起動前プロセス PID `13979` の記録。 |
| [verification-web-routes.log](./verification-web-routes.log) | Google / ChatGPT 導線追加後の `swift test` 成功ログと、再起動した Sagasu プロセス PID `57235` の記録。 |
| [verification-clipboard-rules.log](./verification-clipboard-rules.log) | clipboard retention / image persistence 対応後の runtime ログ。保存済み text entry と image entry の JSON 要約、`clipboard-images/` の PNG 実ファイル、再起動した Sagasu プロセス PID `35832` を記録。 |
| [verification-clipboard-image-preview.log](./verification-clipboard-image-preview.log) | `vi` パーサと image preview UI 対応後の `swift test` 成功ログと、再起動した Sagasu プロセス PID `73578` の記録。 |

### テスト結果
```bash
# Command excerpt
swift test

# Result excerpt
✔ Test defaultsToApplications() passed
✔ Test parsesNotesPrefixCaseInsensitively() passed
✔ Test parsesFilePrefix() passed
✔ Test parsesClipboardPrefix() passed
```

### 確認チェックリスト
- [x] Build / test: `swift test`
- [x] Launcher runtime: `windowCount=1`
- [x] Clipboard persistence: JSON updated
- [ ] Notes automation permission granted on this machine

<details>
<summary>詳細ログ</summary>

```bash
# swift test
Test Suite 'All tests' passed
✔ Test run with 4 tests in 0 suites passed after 0.001 seconds.

# launcher runtime
windowCount=1

# clipboard persistence
[{"id":"2B4F6ACB-A0EB-4A54-A267-34FAB22BACCB","capturedAt":798969641.649148,"text":"artifact clipboard 1777276841"}]

# notes access
NotesにApple Eventsを送信する権限がありません。 (-1743)
```

</details>

### 再現手順
```bash
swift test
swift run Sagasu
# Option + Space でランチャーを表示
# f <query> / n <query> / v <query> で各モードを利用
```

## E2E / 動作健全性レビュー

<details>
<summary>現状のレビュー結果</summary>

| 項目 | 状態 | 内容 |
|------|------|------|
| 自動 E2E | ⚠️ | 今回はネイティブ macOS アプリを空リポジトリから新規作成したため、Playwright 系の E2E は未導入です。 |
| 画面起動確認 | ✅ | `CGWindowList` で `windowCount=1` を確認。 |
| 入力モード切替 | ✅ | `SearchModeParser` の 4 テストで default / `f ` / `n ` / `v ` を確認。 |
| クリップボード保存 | ✅ | `clipboard-history.json` の更新を確認。 |
| Notes 連携 | ⚠️ | 実装済みだが、このマシンでは Apple Events 権限未付与のためアクセス拒否ログを確認。 |

</details>

## 補足
- Notes 検索は未実装ではなく、権限未付与時に明示的なエラーを返す状態です。
- file 検索は Spotlight (`mdfind`) を使い、ユーザー指定の代表ディレクトリにスコープを絞っています。
- クリップボード履歴は `~/Library/Application Support/Sagasu/clipboard-history.json` に保存されます。
