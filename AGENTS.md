# Sagasu Agent Rules

## Language

- Think and report in Japanese.

## Completion Flow

- For every code or documentation change in this project, continue through verification, commit, push, and local app binary replacement before reporting completion.
- Use `swift test` as the baseline verification command.
- Use `Scripts/build_app.sh` to build the release-configuration app bundle at `dist/Sagasu.app`. Its signature follows the requested local identity and may be ad-hoc when that identity is unavailable; only `Scripts/build-and-open-app.sh` may install the app.
- Use `Scripts/build-and-open-app.sh` to install that signed app to `/Applications/Sagasu.app` with the existing Developer ID Application identity, then launch it. The script stages and verifies the replacement before stopping the installed app, and restores the prior app if the replacement move fails.
- Use `Scripts/package_release.sh` when a zip/dmg/checksum artifact is needed; it writes to `dist/release`.
- After replacing the app binary, launch and verify the installed app from `/Applications/Sagasu.app`, because that is the app used by the user's hotkeys and macOS permissions.
- Keep the installed app signed with its stable Developer ID Application identity. `Scripts/build-and-open-app.sh` reuses the identity on the existing `/Applications/Sagasu.app`; for a first install, it requires an available Developer ID Application value in `SAGASU_CODE_SIGN_IDENTITY`. Do not install a differently signed or ad-hoc local copy, because that can split macOS Accessibility permission.
- Do not stop at implementation-only or test-only completion unless the user explicitly asks to pause before commit, push, or binary replacement.

## Git

- Commit only the intended project changes.
- Push the committed branch to `origin` after verification passes.
- Never rewrite or discard unrelated user changes.
