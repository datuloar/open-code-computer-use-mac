# Validation

The initial port is being developed from a Windows workstation. Real macOS desktop behavior
requires validation on an unlocked Mac with the user's privacy permissions. Do not infer GUI
success from compilation or the unit count.

```sh
node scripts/verify.mjs
node test/run.mjs
node scripts/build.mjs
node test/native-smoke.mjs
node test/desktop.mjs
```

The first two checks run without macOS. The build uses Apple's Swift compiler, links public
frameworks and runs native argument/geometry checks. GitHub Actions runs these separately on
Apple Silicon and Intel. Native smoke checks start the actual helper and MCP path, inspect
permissions and reject malformed input without starting control. No privacy grants are assumed.

The desktop test is opt-in and uses only its own fixture. It verifies field typing, inspection,
named clicks and cleanup, then preserves a JSON report. Physical Escape, Stop-button behavior,
Retina appearance, third-party app coverage and interaction with other monitors need human review.

No autonomous provider task, token-cost comparison, Paint-style drawing benchmark or superiority
claim is inherited from the Windows distribution. Record the tested commit, architecture, macOS
version, permissions and observed result when reporting a Mac problem. Keep user screenshots,
config files and credentials out of issue reports.
