# Sagasu

Sagasu is a small macOS launcher for applications, files, Apple Notes, web routes, and clipboard history.

## Launching

- Press `Option-Space` to open or close Sagasu.
- Type normally to search applications. Google and ChatGPT routes are also shown for non-empty application searches.
- Select a result and press `Return` to run it.

## Search prefixes

- `f ` searches files and folders.
- `F ` with no query shows recently modified folders.
- `n ` searches Apple Notes.
- `v ` searches clipboard text and image history.
- `vi ` searches clipboard images only.

When Sagasu opens with an empty query, recently modified folders are mixed near the top of the default application list. This makes recent work folders available immediately without switching modes. If you type `f ` first, Sagasu switches to folder/file mode and only folder/file results are shown.

## History behavior

- Clipboard entries move upward after they are restored.
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
