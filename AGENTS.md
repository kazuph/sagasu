# Sagasu Agent Rules

## Language

- Think and report in Japanese.

## Completion Flow

- For every code or documentation change in this project, continue through verification, commit, push, and local app binary replacement before reporting completion.
- Use `swift test` as the baseline verification command.
- Use `Scripts/build-and-open-app.sh` to rebuild `.build/Sagasu.app`, replace `.build/Sagasu.app/Contents/MacOS/Sagasu`, install the rebuilt app to `~/Applications/Sagasu.app`, and replace `~/Applications/Sagasu.app/Contents/MacOS/Sagasu` with the latest compiled binary.
- After replacing the app binary, launch and verify the installed app from `~/Applications/Sagasu.app`, because that is the app used by the user's hotkeys and macOS permissions.
- Keep the installed app signed with a stable code-signing identity. `Scripts/build-and-open-app.sh` prefers `SAGASU_CODE_SIGN_IDENTITY` or `Apple Development: Kazuhiro Homma (283LEN7F9Y)`. Do not leave the installed app ad-hoc signed unless no signing identity is available, because that can break macOS Accessibility permission on every rebuild.
- Do not stop at implementation-only or test-only completion unless the user explicitly asks to pause before commit, push, or binary replacement.

## Git

- Commit only the intended project changes.
- Push the committed branch to `origin` after verification passes.
- Never rewrite or discard unrelated user changes.
