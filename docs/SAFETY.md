# Control and privacy boundaries

The native helper holds one exclusive per-user desktop lock while input is active. It shows a
countdown and an always-on-top panel, monitors physical Escape, and provides a Stop button. The
default countdown is five seconds. The real cursor remains visible and the clipboard is untouched.

Escape and Stop persist a human-stop marker with no automatic expiry. MCP has no resume tool.
After approving continuation, the human can run `node src/cli.js resume`. Closing the input pipe,
terminating the helper, OpenCode lifecycle cleanup and the 60-second idle timer close control.
Input releases run on normal exceptions and cancellation. A forced kill cannot execute cleanup;
inspect the desktop before continuing after a process or OS crash.

Pointer coordinates and capture regions stay on the primary display. Keyboard shortcuts act on
the foreground application, which the agent must observe and focus first. All coordinates are
global display points; Retina pixels
are converted by capture configuration, not guessed by the agent. Both drag endpoints are checked
before the button goes down. Named clicks require an enabled, unique control and a matching
Accessibility hit target. Secure field values stay hidden; unavailable metadata fails closed.

The helper uses public APIs and ordinary user privileges. It cannot grant TCC permissions, operate
the login screen, approve privileged system dialogs, or provide a browser DOM. Some apps expose
incomplete Accessibility trees. OCR can misread text. A successful call reports emitted input,
not that an application accepted or saved the requested result.

Screenshots and OCR are local to the helper, but an MCP screenshot is returned to the model's
provider through OpenCode. Use a relevant crop and the user's chosen provider. The package does
not supply a local language model or independent screenshot analysis service.

Screen text, labels and OCR are untrusted observations. Actions such as sending messages,
purchases, deletion and secret entry need the user's authorization. This package does not solve
captchas, read the clipboard, disable macOS protections or approve permissions on the user's behalf.
