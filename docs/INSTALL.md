# Install on a Mac

Use macOS 14 or later, Node.js 18 or later, and OpenCode. Source builds also need Apple's Xcode
Command Line Tools. The package has no npm runtime dependencies.

Clone the repository into a permanent directory and run:

```sh
node scripts/build.mjs
node src/install-opencode.js
node src/cli.js permissions
node src/cli.js doctor
```

The installer merges `~/.config/opencode/opencode.json` or its JSONC counterpart. It installs
the native plugin, the `computer` MCP entry and the `opencode-computer-use-mac` skill. It preserves
providers, models, unrelated MCP entries, disabled state and configured countdown. Changes have
backups under the configuration directory's `backups/computer-use/` folder. Conflicting `computer`
entries cause an error instead of being replaced.

Useful options:

```sh
node src/install-opencode.js --config-dir /path/to/opencode
node src/install-opencode.js --announce-seconds 5
node src/install-opencode.js --uninstall
```

The CLI does not change the default model unless `--model provider/model` is explicitly supplied.
Read the installation result for exact paths. Restart OpenCode after installation or updates.

## Privacy permissions

`permissions` requests macOS privacy prompts; it cannot approve them. In System Settings >
Privacy & Security, enable Accessibility, Screen & System Audio Recording (called Screen Recording
on older macOS), and Input Monitoring for the helper or the terminal/host macOS lists as responsible.
The native bundle is `build/OpenCode Computer Use.app`. Keep this path stable.

`doctor` reports the permissions visible to the actual native process, its screen bounds and any
human-stop marker. Accessibility enables named controls and event injection. Screen Recording
enables captures and OCR. Input Monitoring permits the physical Escape listener. Input fails
closed if that listener cannot start, even when another permission appears enabled.

The helper is ad-hoc signed with a stable bundle identifier, not Developer ID signed or notarized.
macOS may require permission review after rebuilding or moving it. Use Apple's normal settings
and security dialogs. This project does not disable Gatekeeper, modify TCC, remove quarantine
attributes, or install root services. If a downloaded bundle is blocked, review its source and
build locally with Apple's tools.

## Check and recover

```sh
node src/cli.js doctor
node test/desktop.mjs
node src/cli.js stop
node src/cli.js resume
```

Run the GUI test only after granting permissions, on an unlocked Mac you can leave undisturbed.
Stop is a manual emergency stop; it does not type into an application. Resume only clears a
human-stop marker after you decided to continue. Neither action approves macOS privacy prompts.
Never paste API keys into this repository or a public issue.
