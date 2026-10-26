# Validation

The initial port is developed from a Windows workstation. Real macOS desktop behavior
requires validation on an unlocked Mac with the user's privacy permissions. Do not infer GUI
success from compilation or the unit count.

```sh
node scripts/verify.mjs
node test/run.mjs
node scripts/build.mjs
node test/native-smoke.mjs
node test/opencode-smoke.mjs
node test/desktop.mjs
```

The first two checks run without macOS. The build uses Apple's Swift compiler, links public
frameworks and runs native argument/geometry checks. GitHub Actions runs these separately on
Apple Silicon and Intel. Native smoke checks start the actual helper and MCP path, inspect
permissions and reject malformed input without starting control. No privacy grants are assumed.

The OpenCode smoke check uses the real installed OpenCode CLI with isolated temporary config,
data and cache directories. It checks plugin loading, agent instructions, skill discovery and MCP
connection without contacting a model or injecting input. Set `OPENCODE_EXECUTABLE` if the
executable is not on PATH. Its report stays in a temporary directory.

CI pins OpenCode 1.18.25 for this integration check on both Mac architectures. The same check
passed with OpenCode 1.18.25 on the Windows development workstation on October 25, 2026; that
result establishes host integration only. The Node unit suite covers validation, cancellation of
active and queued commands, host recovery, installer preservation, ownership hooks and packaging.
Current native build results are recorded in [GitHub Actions](https://github.com/datuloar/open-code-computer-use-mac/actions).

The desktop test is opt-in and uses only its own fixture. It verifies field typing, inspection,
named clicks, external cancellation and cleanup, then preserves a JSON report. The fixture
explicitly exposes its editor as enabled and disables automatic text substitutions, including
double-space-to-period replacement through process-local launch arguments. User keyboard
preferences are not changed. Physical Escape, Stop-button behavior,
Retina appearance, third-party app coverage and interaction with other monitors need human review.

On October 26, 2026, all nine desktop checks passed on an Apple Silicon Mac running macOS 26.6.2
(25G83), using Node.js 24.22.1 and the local fixes on top of commit `c153fcd`. Accessibility,
Input Monitoring, event posting and Screen Recording were available to the actual helper process.
This run reproduced and fixed an AppKit main-thread crash during control startup. Asynchronous
dispatch, session startup and input now stay on `MainActor`, including after suspension.
The result covers the owned fixture on that Mac, not Intel desktop input or arbitrary applications.

No autonomous provider task, token-cost comparison, Paint-style drawing benchmark or superiority
claim is inherited from the Windows distribution. Record the tested commit, architecture, macOS
version, permissions and observed result when reporting a Mac problem. Keep user screenshots,
config files and credentials out of issue reports.
