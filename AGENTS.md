# Sagasu Agent Rules

## Language

- Think and report in Japanese.

## Completion Flow

- Treat verification, commit, push, merge, tagged GitHub Release publication, Homebrew cask update, and `brew upgrade --cask kazuph/tap/sagasu` on this Mac as one completion flow. Do not report completion after only merging source or replacing a local binary.
- Publish signed and notarized ZIP/DMG/checksum assets through the release workflow. Update `Casks/sagasu.rb` in `kazuph/homebrew-tap` to the published version and verified DMG SHA-256, then merge and synchronize the tap before upgrading.
- After the Homebrew upgrade, launch `/Applications/Sagasu.app` and verify its version, stable Developer ID identity, notarization, and the changed behavior with real user operations. Report source, public release, Homebrew, installed version, and verification separately.
- Use `swift test` as the baseline verification command.
- Use `Scripts/build_app.sh` to build the release-configuration app bundle at `dist/Sagasu.app`. Its signature follows the requested local identity and may be ad-hoc when that identity is unavailable; only `Scripts/build-and-open-app.sh` may install a locally built app; use Homebrew for the final published app upgrade.
- Use `Scripts/build-and-open-app.sh` to install that signed app to `/Applications/Sagasu.app` with the existing Developer ID Application identity, then launch it. The script stages and verifies the replacement before stopping the installed app, and restores the prior app if the replacement move fails.
- Use `Scripts/package_release.sh` when a zip/dmg/checksum artifact is needed; it writes to `dist/release`.
- After replacing the app binary, launch and verify the installed app from `/Applications/Sagasu.app`, because that is the app used by the user's hotkeys and macOS permissions.
- Keep the installed app signed with its stable Developer ID Application identity. `Scripts/build-and-open-app.sh` reuses the identity on the existing `/Applications/Sagasu.app`; for a first install, it requires an available Developer ID Application value in `SAGASU_CODE_SIGN_IDENTITY`. Do not install a differently signed or ad-hoc local copy, because that can split macOS Accessibility permission.
- Do not stop at implementation, tests, merge, or a local install unless the user explicitly limits the requested scope. Public release, Homebrew delivery, and the installed-app verification above are required for the full flow.

## Git

- Commit only the intended project changes.
- Push the committed branch to `origin` after verification passes.
- Never rewrite or discard unrelated user changes.
