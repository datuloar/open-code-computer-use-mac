# Native indicator

The user asked for OpenCode's visual style. The panel uses its existing dark neutral and peach
direction: background #141414, foreground #fab283, system monospaced text, and one native Stop
button. This is a status and cancellation surface, not a second application toolbar.

The panel names OpenCode, the countdown or current action, and Escape. It does not take keyboard
focus from the target app. Typed text appears only as a count. A native button supports an
accessible label and a pointer-based stop path. The real system cursor stays visible.

Text contrast is 10.32:1 against the panel background using relative luminance. AppKit lays out
the panel in points for Retina. The initial port still needs human inspection of appearance,
VoiceOver, Spaces and fullscreen apps on a real Mac. These checks have not been claimed as passed.
