# Installation instructions for agents

1. Confirm the target is macOS 14 or later and Node.js 18 or later is installed. Keep the checkout
   in a permanent directory. Do not install this backend into a Windows checkout.
2. Inspect the existing OpenCode config without printing credentials. The `computer` MCP name must
   be free or already refer to this checkout. Preserve unrelated entries and the selected provider.
3. Build with `node scripts/build.mjs` if no native bundle is present. It uses Apple's compiler;
   if Command Line Tools are absent, ask the user to install them with `xcode-select --install`.
4. Run `node src/install-opencode.js`. Keep the reported backup path. Never replace the entire
   user config with an example. Do not choose a paid provider or change keys to make a test pass.
5. Ask the user to approve privacy permissions. `node src/cli.js permissions` opens the system
   request path; only the user can grant access. Run `doctor` afterward and restart OpenCode.
6. Verify that the native plugin, `computer` entry and `opencode-computer-use-mac` skill load.
   An MCP connection alone does not establish input permissions or task success.
7. With the user's authorization, run `node test/desktop.mjs`. It owns a fixture window and writes
   a local report. Preserve failures. Do not inject test input into the user's current app.

For operation, read [the skill](../opencode/SKILL.md). Use Accessibility names before OCR or images,
screen points rather than Retina pixels, and Cmd shortcuts. Stop the indicator before leaving
desktop tools. A human stop requires explicit approval and manual resume; never remove its state.

For an update, pull the existing checkout, rebuild the helper, rerun the installer, and restart
OpenCode. Re-check permissions if macOS no longer trusts the rebuilt helper. Run static and native
checks before claiming that the update is ready. Report untested GUI behavior explicitly.
