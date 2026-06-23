# Sagasu

Sagasu is a small macOS launcher for applications, files, Apple Notes, web routes, and clipboard history.

## Launching

- Press `Command-Space` to open or close Sagasu.
- Press `Command-Shift-V` to open Sagasu directly in clipboard history mode with `v ` prefilled.
- Sagasu switches the keyboard input source to an ASCII-capable layout when the launcher search field is focused.
- Type normally to search applications. Google and ChatGPT routes are also shown for non-empty application searches.
- Click a prefix button below the search field to insert that prefix plus a space and switch modes without typing it manually.
- Select a result and press `Return` to run it.

## Search prefixes

- `f ` searches files and folders. Common directories such as Downloads, Documents, Music, Movies, and Pictures are prioritized, so `f d` can quickly open Downloads or Documents.
- `F ` with no query shows recently modified folders.
- `d ` searches directories only.
- `t ` searches Herdr panes by project directory, agent, status, workspace, or pane id. Pressing `Return` focuses that Herdr pane and activates the terminal app.
- `n ` searches Apple Notes.
- `v ` searches clipboard text and image history.
- `vi ` searches clipboard images only.
- `g ` searches repositories owned by you and your GitHub organizations when `gh` is available. Local `ghq list` matches are shown first when `ghq` is installed.
- `gh ` searches repositories across GitHub when `gh` is available.
- `gi ` searches issues in repositories owned by you and your GitHub organizations when `gh` is available.
- `gp ` searches pull requests in repositories owned by you and your GitHub organizations when `gh` is available.
- `ghq ` searches only local `ghq list` entries.
- `l ` searches Linear issues. On first use, Sagasu asks for a personal Linear API key and stores it in macOS Keychain.

When Sagasu opens with an empty query, recently modified folders are mixed near the top of the default application list. This makes recent work folders available immediately without switching modes. If you type `f ` first, Sagasu switches to folder/file mode and only folder/file results are shown.
Finder is indexed from `/System/Library/CoreServices`, so typing `finder` opens Finder from the application list.
If the system clipboard contains an image, the default application search includes `Image: Save Clipboard Image` and `Image: Extract Text from Clipboard Image`. They are searchable with English terms such as `i`, `image`, `ocr`, `text`, `extract`, `save`, or `downloads`. Saving writes a PNG to `~/Downloads`; extracting Japanese and English text copies recognized text back to the system clipboard and adds it to the latest clipboard history.
GitHub search results open in Chrome. Sagasu enables these modes automatically when the `gh` command is installed; `ghq` results are enabled automatically when the `ghq` command is installed.
Linear search results open in Chrome. Sagasu calls Linear's GraphQL API directly and sends personal API keys as `Authorization: <API_KEY>`, matching Linear's personal API key authentication.

## History behavior

- Clipboard entries move upward after they are restored, and Sagasu sends `Command-V` after selection so the restored entry is pasted into the previously active app.
- Applications move upward after they are launched from Sagasu.
- Opened file and folder URLs are recorded for future ranking.
- Clipboard entries expire after 3 months by default. Reusing an entry extends it to 6 months from last use. Pinned entries do not expire.

## Clipboard commands

- `Command-P` toggles pinning for the selected clipboard entry.
- `Command-D` deletes the selected clipboard entry.

## Window management

Sagasu includes fixed Raycast-style window management shortcuts. These do not currently have settings UI.

| Shortcut | Action |
| --- | --- |
| `Control-Shift-Command-J` | Bottom height cycle |
| `Control-Shift-Command-I` | Center third |
| `Control-Shift-Command-H` | Left width cycle |
| `Control-Shift-Command-Return` | Maximize |
| `Control-Shift-Command-Y` | Next display |
| `Control-Shift-Command-P` | Previous display |
| `Control-Shift-Command-L` | Right width cycle |
| `Control-Shift-Command-K` | Top height cycle |

The H/J/K/L commands cycle by inspecting the current window frame, not by counting rapid key presses. The cycle is `1/2 -> 1/3 -> 1/4 -> 2/3 -> 3/4 -> 1/2`.

Window management uses macOS Accessibility. If the shortcuts do not move windows, grant Sagasu permission in System Settings > Privacy & Security > Accessibility.
`Scripts/build-and-open-app.sh` signs Sagasu with a stable Apple Development identity when available so macOS can keep the Accessibility permission across rebuilds. If the app is ad-hoc signed, macOS may require removing and adding Sagasu again in Accessibility because the app's code signature changes.
If macOS opens the input source or Character Viewer popover when using Sagasu's launch shortcut, disable the conflicting macOS keyboard shortcuts for `Command-Space` and `Command-Shift-Space`.

## Development

```sh
swift test
make app
make install
make package
```

`make app` builds a signed release app at `dist/Sagasu.app`. `make install`
copies that signed app to `~/Applications/Sagasu.app` and launches it. `make
package` creates `Sagasu-<version>.zip`, `Sagasu-<version>.dmg`, and
`checksums.txt` under `dist/release`.
