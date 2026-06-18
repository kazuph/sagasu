# Sagasu Agent Rules

## Language

- Think and report in Japanese.

## Completion Flow

- For every code or documentation change in this project, continue through verification, commit, push, and local app binary replacement before reporting completion.
- Use `swift test` as the baseline verification command.
- Use `Scripts/build-and-open-app.sh` to rebuild `.build/Sagasu.app` and replace `.build/Sagasu.app/Contents/MacOS/Sagasu` with the latest compiled binary.
- After replacing the app binary, launch the rebuilt app from `.build/Sagasu.app` when runtime verification is relevant.
- Do not stop at implementation-only or test-only completion unless the user explicitly asks to pause before commit, push, or binary replacement.

## Git

- Commit only the intended project changes.
- Push the committed branch to `origin` after verification passes.
- Never rewrite or discard unrelated user changes.
