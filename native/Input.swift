import AppKit
import ApplicationServices

enum Input {
    static var heldKeys = Set<CGKeyCode>()
    static var heldButton: CGMouseButton?
    static var currentPoint = CGPoint.zero
    static let keyMap: [String: CGKeyCode] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "backspace": 51, "delete": 51, "escape": 53, "esc": 53, "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "forwarddelete": 117, "left": 123, "right": 124, "down": 125, "up": 126, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111]
    static let modifiers: [String: (CGKeyCode, CGEventFlags)] = ["cmd": (55, .maskCommand), "command": (55, .maskCommand), "shift": (56, .maskShift), "option": (58, .maskAlternate), "alt": (58, .maskAlternate), "ctrl": (59, .maskControl), "control": (59, .maskControl)]

    static func keys(_ value: String) throws -> ([CGKeyCode], CGKeyCode, CGEventFlags) {
        let parts = value.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last, let key = keyMap[last], parts.count <= 5 else { throw Failure("Unknown key combination; use named keys such as cmd+a or option+left") }
        var codes: [CGKeyCode] = []
        var flags = CGEventFlags()
        for part in parts.dropLast() {
            guard let modifier = modifiers[part], !codes.contains(modifier.0) else { throw Failure("Unknown or duplicate modifier") }
            codes.append(modifier.0)
            flags.insert(modifier.1)
        }
        return (codes, key, flags)
    }

    static func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        if down { heldKeys.insert(code) } else { heldKeys.remove(code) }
    }

    static func releaseAll() {
        for code in Array(heldKeys) { key(code, down: false) }
        if let button = heldButton { mouse(button == .left ? .leftMouseUp : button == .right ? .rightMouseUp : .otherMouseUp, currentPoint, button) }
        heldButton = nil
    }

    static func mouse(_ type: CGEventType, _ location: CGPoint, _ button: CGMouseButton = .left, count: Int = 1) {
        currentPoint = location
        if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: button) {
            event.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            event.post(tap: .cghidEventTap)
        }
    }

    static func click(_ location: CGPoint, mode: String) async throws {
        try ControlSession.shared.checkpoint()
        let button: CGMouseButton = mode == "right" ? .right : mode == "middle" ? .center : .left
        let count = mode == "double" ? 2 : mode == "triple" ? 3 : 1
        defer { releaseAll() }
        for index in 1...count {
            try ControlSession.shared.checkpoint()
            heldButton = button
            mouse(button == .left ? .leftMouseDown : button == .right ? .rightMouseDown : .otherMouseDown, location, button, count: index)
            try await pause(0.04)
            mouse(button == .left ? .leftMouseUp : button == .right ? .rightMouseUp : .otherMouseUp, location, button, count: index)
            heldButton = nil
            try await pause(0.05)
        }
    }

    static func drag(_ from: CGPoint, _ to: CGPoint) async throws {
        try ControlSession.shared.checkpoint()
        defer { releaseAll() }
        mouse(.mouseMoved, from)
        heldButton = .left
        mouse(.leftMouseDown, from)
        for step in 1...30 {
            try await pause(0.02)
            try ControlSession.shared.checkpoint()
            let progress = Double(step) / 30
            mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress))
        }
        mouse(.leftMouseUp, to)
        heldButton = nil
    }

    static func press(_ combo: String) async throws {
        let (codes, code, flags) = try keys(combo)
        try ControlSession.shared.checkpoint()
        defer { releaseAll() }
        for modifier in codes { key(modifier, down: true, flags: flags) }
        key(code, down: true, flags: flags)
        try await pause(0.03)
        key(code, down: false, flags: flags)
    }

    static func type(_ value: String) async throws -> Int {
        var sent = 0
        for character in value {
            try ControlSession.shared.checkpoint()
            if character == "\r" { continue }
            if character == "\n" { try await press("return") }
            else if character == "\t" { try await press("tab") }
            else {
                let units = Array(String(character).utf16)
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { throw Failure("Cannot create Unicode key event") }
                units.withUnsafeBufferPointer { buffer in
                    down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress!)
                    up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress!)
                }
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            sent += 1
            try await pause(0.01)
        }
        return sent
    }
}
