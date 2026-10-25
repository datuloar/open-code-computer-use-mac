# OpenCode Computer Use for macOS

Maintain this repository separately from the Windows distribution. All product documentation is
English. The package is `opencode-computer-use-mac`, the skill has the same name, the OpenCode MCP
entry is `computer`, and the CLI is `opencode-cu-mac`.

- No code comments. Explain invariants here or in documentation.
- `src/commands.js` defines tool names, schemas and routing for CLI and MCP. Validate before input.
- `native/` contains the Swift backend. Use public Apple APIs, without third-party dependencies.
- Coordinates are macOS global display points with a top-left origin. Captures use one output
  pixel per point. The primary display is the supported input surface; never guess Retina scaling.
- Input requires Accessibility and a functioning physical Escape monitor, an exclusive desktop
  lock, a visible countdown, and a live session. Keep the real cursor visible.
- Physical Escape and the Stop button persist a human-stop marker. Only an explicit manual
  `resume` command clears it. MCP must never clear or age out a human stop.
- Release held keys and mouse buttons during cancellation, exceptions, timeout and shutdown.
- Stop files bind both owner and session token. Never kill another process using a recorded PID.
- Keep the state directory private, lock it with `flock`, and publish state atomically.
- Named input must resolve one visible enabled control. Exact names precede enabled filtering.
  Inspect password subroles before reading values and fail closed when metadata is unavailable.
- Bound trees, text, coordinates, protocol output and backend timeouts. Do not replay partial input.
- The native indicator shares the backend process. Pipe closure and signals must close control.
- Do not read the clipboard, approve privacy dialogs, or grant permissions programmatically.
- Installation preserves unrelated OpenCode configuration and backs up changed files.
- Source builds and release bundles use a stable app identity. Ad-hoc signing is not notarization.
- CI builds and checks both Apple Silicon and Intel. CI without privacy permissions is not a GUI
  success. Run `node test/desktop.mjs` only on an unlocked Mac with the user's authorization.
- Keep raw screenshots, user config, credentials and local GUI reports out of Git.

Run `node scripts/verify.mjs`, `node test/run.mjs`, and on macOS `node scripts/build.mjs` and
`node test/native-smoke.mjs`. Review `docs/VALIDATION.md` before claiming desktop verification.
