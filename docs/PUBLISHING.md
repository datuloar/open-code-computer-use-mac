# Build and publish

The repository and GitHub Releases are the distribution. There is no npm publishing step.
Version 1.0.0 is a macOS preview until the interactive desktop checks have been run on a user Mac.

On macOS:

```sh
node scripts/verify.mjs
node test/run.mjs
node scripts/build.mjs
node test/native-smoke.mjs
node scripts/package.mjs --native
```

The packager produces an architecture-specific ZIP and its SHA-256 checksum under `dist/`.
`arm64` is Apple Silicon; `x64` is Intel. Both archives include the app bundle, source, tests,
installer and English agent instructions. They contain no runtime npm dependencies or user
configuration. `PACKAGE-MANIFEST.json` records individual file hashes. Check a fresh extraction
with `node scripts/package.mjs --check .` before installation. Hashes detect accidental changes;
they are not a substitute for a trusted release or a Developer ID signature.
Before producing its checksum, the packager also extracts the ZIP, rechecks every file, verifies
the app's signature and runs the extracted helper's native checks.

Keep `package.json` and `native/Info.plist` versions equal. The release workflow requires the
exact tag `v` followed by that version, such as `v1.0.0`. A mismatch is a failed release; do not
remove the version check or retag an already published version.

After reviewing the commit and successful CI, tag it and push:

```sh
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions builds on `macos-15` and `macos-15-intel`, runs native smoke checks, packages both
architectures, checks integration with OpenCode 1.18.25 and publishes four assets: two ZIP files
and two checksum files. Publication waits
for both builds. The release is marked as a prerelease while real desktop validation is pending.
Source builds and release bundles are ad-hoc signed. Do not describe them as notarized.

The `verify` workflow also runs on normal pushes and pull requests. GUI testing is intentionally
manual: CI never approves privacy prompts or presents a compilation result as desktop success.
