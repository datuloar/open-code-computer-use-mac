# OpenCode Computer Use for macOS

Native macOS desktop tools for OpenCode. The backend uses Apple's Accessibility APIs,
ScreenCaptureKit, Vision OCR and Core Graphics input. A visible countdown and physical Escape
govern input. The real cursor stays visible.

This independent integration requires macOS 14 or later and Node.js 18 or later. Apple Silicon
and Intel builds are checked separately. It is not an official OpenCode product.

## Install a release

Download the ZIP and matching checksum from [Releases](https://github.com/datuloar/open-code-computer-use-mac/releases).
Choose `arm64` for Apple Silicon or `x64` for Intel. Verify the ZIP before extraction:

```sh
shasum -a 256 -c opencode-computer-use-mac-1.0.0-arm64.zip.sha256
```

Use the `x64` filename for Intel. Extract the archive into a permanent folder, open Terminal in
`opencode-computer-use-mac`, then run:

```sh
sh install.sh
node src/cli.js permissions
node src/cli.js doctor
```

The release contains a compiled helper, so Command Line Tools are only needed for source builds.
Version 1.0.0 is a preview: both native architectures compile and pass permission-free checks;
actual desktop input still needs verification on a user Mac. The helper is ad-hoc signed, not
notarized. Follow [installation](docs/INSTALL.md) if macOS blocks a downloaded bundle.

## Install from source

```sh
git clone https://github.com/datuloar/open-code-computer-use-mac.git
cd open-code-computer-use-mac
xcode-select --install
node scripts/build.mjs
sh install.sh
node src/cli.js permissions
node src/cli.js doctor
```

Skip `xcode-select --install` if Command Line Tools are already installed. Keep the repository
at a stable location; the OpenCode configuration points to this checkout. Approve Accessibility,
Screen Recording and Input Monitoring for the helper or its launching terminal as listed in
System Settings. Restart OpenCode after changing permissions. The installer never grants them.

See [installation](docs/INSTALL.md), [agent setup](docs/AGENT_SETUP.md),
[safety and limits](docs/SAFETY.md), and [validation](docs/VALIDATION.md).
All documentation and agent instructions are English.

## Use

Ask OpenCode to work in an application. The plugin supplies instructions and discovers the
`opencode-computer-use-mac` skill. It prefers named controls, then cropped OCR or screenshots.
It uses `computer_*` tools for desktop work and stops control before ordinary coding tools.

Coordinates are screen points, including on Retina displays. Screenshots use one pixel per
point. Only the primary display supports input. A text-only model can use Accessibility and
OCR; viewing screenshots requires an image-capable model.

```sh
node src/cli.js windows
node src/cli.js ui_tree '{"pid":1234}'
node src/cli.js find '{"pid":1234,"text":"Save","role":"AXButton"}'
node src/cli.js --help
```

Each CLI invocation closes its own session. MCP keeps a warm backend for related actions.
The countdown defaults to five seconds; set `OPENCODE_CU_ANNOUNCE_SECONDS` from 0 to 30 through
the installer's `--announce-seconds` option. Reinstalling preserves the existing setting.
Escape and the panel's Stop button persist a human stop. Only the human can clear it with
`node src/cli.js resume` after approving continuation.

## Development

```sh
node scripts/verify.mjs
node test/run.mjs
node scripts/build.mjs
node test/native-smoke.mjs
node test/opencode-smoke.mjs
node test/desktop.mjs
```

The final command drives only its dedicated fixture on an unlocked Mac. CI compilation and
permission-free checks do not certify real desktop input. See [AGENTS.md](AGENTS.md) for invariants.
The OpenCode smoke check requires an installed `opencode` executable and uses temporary config.
See [publishing](docs/PUBLISHING.md) for packages, checksums and matching release tags.

The Node host and OpenCode lifecycle integration share MIT-licensed work from
[OpenCode Computer Use for Windows](https://github.com/datuloar/open-code-computer-use-win).
This repository has its own native backend, installation, builds and releases.
