import AppKit
import ApplicationServices

enum Dispatcher {
    static let tools = Set(["doctor", "permissions", "resume", "windows", "ui_tree", "find", "tap", "focus", "screenshot", "read_text", "click", "move", "drag", "scroll", "type", "press", "indicator"])
    static let input = Set(["tap", "focus", "click", "move", "drag", "scroll", "type", "press"])

    static func run(_ request: [String: Any]) async throws -> [String: Any] {
        guard let command = request["command"] as? String, tools.contains(command), let args = request["arguments"] as? [String: Any], let owner = request["owner"] as? String, !owner.isEmpty, owner.count <= 200 else { throw Failure("Invalid native request") }
        let session = ControlSession.shared
        let seconds = try number(request, "announceSeconds", fallback: 5)
        guard seconds >= 0, seconds <= 30, seconds.rounded() == seconds else { throw Failure("Countdown must be an integer from 0 to 30") }
        if ["click", "move", "drag"].contains(command) { _ = try point(args) }
        if command == "drag" { _ = try point(args, "to_x", "to_y") }
        if command == "click", let mode = args["button"] as? String, !["left", "right", "middle", "double", "triple"].contains(mode) { throw Failure("Invalid click button") }
        if command == "press" { _ = try Input.keys(text(args, "keys")) }
        if command == "type" || command == "find" || command == "tap" { _ = try text(args, "text") }
        if command == "focus", args["pid"] == nil && args["window"] == nil { throw Failure("Focus requires a target") }
        if command == "scroll" {
            let notches = try number(args, "notches")
            guard notches != 0, abs(notches) <= 100, notches.rounded() == notches else { throw Failure("Scroll notches must be a nonzero integer from -100 to 100") }
            if args["x"] != nil || args["y"] != nil { _ = try point(args) }
            else { _ = try pointer() }
        }
        if input.contains(command) {
            if command == "tap" { _ = try selected(args) }
            if command == "focus" { _ = try Accessibility.target(args, allowMinimized: true) }
            try await session.begin(owner: owner, seconds: Int(seconds))
            try session.checkpoint()
            session.setAction(command == "type" ? "Type \((args["text"] as? String)?.count ?? 0) characters" : command.capitalized)
        } else if session.owner == owner { session.lastTouch = Date() }
        var result: [String: Any]
        switch command {
        case "doctor":
            result = ["platform": "macOS", "version": ProcessInfo.processInfo.operatingSystemVersionString, "permissions": permissions(), "display": rectData(primaryBounds()), "coordinateSpace": "screen points", "humanStopped": FileManager.default.fileExists(atPath: session.humanStopURL.path)]
        case "permissions":
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            _ = CGRequestScreenCaptureAccess()
            _ = CGRequestListenEventAccess()
            result = ["permissions": permissions(), "next": "Approve the helper or launching app in Privacy & Security and restart OpenCode. This command cannot grant permission."]
        case "resume":
            try session.resume()
            result = ["resumed": true, "controlOn": false]
        case "windows":
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            var windows: [[String: Any]] = []
            for entry in info where entry[kCGWindowLayer as String] as? Int == 0 {
                guard let identifier = entry[kCGWindowOwnerPID as String] as? Int, identifier != Int(getpid()), let bounds = entry[kCGWindowBounds as String] as? [String: Any], let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.intersects(primaryBounds()) else { continue }
                windows.append(["pid": identifier, "title": entry[kCGWindowName as String] as? String ?? "", "app": entry[kCGWindowOwnerName as String] as? String ?? "", "bounds": rectData(rect)])
            }
            result = ["windows": Array(windows.prefix(60)), "truncated": windows.count > 60, "coordinateSpace": "screen points"]
        case "ui_tree":
            let depth = try number(args, "depth", fallback: 6)
            guard depth >= 1, depth <= 14, depth.rounded() == depth else { throw Failure("Tree depth must be 1 to 14") }
            let nodes = try Accessibility.collect(Accessibility.target(args), depth: Int(depth))
            result = ["controls": Array(nodes.prefix(120).map { $0.data }), "truncated": nodes.count > 120, "coordinateSpace": "screen points"]
        case "find":
            let needle = try text(args, "text")
            let nodes = try Accessibility.matches(Accessibility.collect(Accessibility.target(args)), needle: needle, role: args["role"] as? String)
            if args["details"] as? Bool == true {
                let limit = try number(args, "max_chars", fallback: 1000)
                guard limit >= 1, limit <= 2000, limit.rounded() == limit else { throw Failure("max_chars must be 1 to 2000") }
                result = Accessibility.inspect(try Accessibility.select(nodes, needle: needle, optional: true), limit: Int(limit))
            } else { result = ["matches": Array(nodes.prefix(20).map { $0.data }), "truncated": nodes.count > 20] }
        case "tap":
            let node = try selected(args)
            try Accessibility.verifyHit(node)
            try await Input.click(CGPoint(x: node.bounds.midX, y: node.bounds.midY), mode: "left")
            result = ["clicked": node.data]
        case "focus":
            let window = try Accessibility.target(args, allowMinimized: true)
            try Accessibility.focus(window)
            try await pause(0.2)
            try session.checkpoint()
            var identifier: pid_t = 0
            AXUIElementGetPid(window, &identifier)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == identifier else { throw Failure("The target did not become foreground") }
            result = ["focused": Accessibility.string(window, kAXTitleAttribute), "pid": identifier]
        case "screenshot": result = try await Capture.screenshot(args)
        case "read_text": result = try await Capture.ocr(args)
        case "move":
            Input.mouse(.mouseMoved, try point(args))
            result = ["moved": true]
        case "click":
            try await Input.click(point(args), mode: args["button"] as? String ?? "left")
            result = ["clicked": true]
        case "drag":
            try await Input.drag(point(args), point(args, "to_x", "to_y"))
            result = ["dragged": true]
        case "press":
            try await Input.press(text(args, "keys"))
            result = ["pressed": true]
        case "type":
            result = ["typedCharacters": try await Input.type(text(args, "text"))]
        case "scroll":
            let location = args["x"] != nil ? try point(args) : try pointer()
            if args["x"] != nil { Input.mouse(.mouseMoved, location) }
            let notches = Int32(try number(args, "notches"))
            let horizontal = args["horizontal"] as? Bool == true
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: horizontal ? 0 : notches, wheel2: horizontal ? notches : 0, wheel3: 0) else { throw Failure("Cannot create scroll event") }
            event.location = location
            event.post(tap: .cghidEventTap)
            result = ["scrolled": true]
        case "indicator":
            let action = try text(args, "action")
            if action == "start" { try await session.begin(owner: owner, seconds: Int(seconds)) }
            else if action == "stop" {
                guard session.owner.isEmpty || session.owner == owner else { throw Failure("Another client owns control") }
                session.stop()
            } else if action != "status" { throw Failure("Unknown indicator action") }
            result = ["ready": session.ready, "humanStopped": FileManager.default.fileExists(atPath: session.humanStopURL.path)]
        default: throw Failure("Unknown command")
        }
        result["controlOn"] = session.ready && session.owner == owner
        return result
    }

    static func selected(_ args: [String: Any]) throws -> Accessibility.Node {
        let needle = try text(args, "text")
        let nodes = try Accessibility.matches(Accessibility.collect(Accessibility.target(args)), needle: needle, role: args["role"] as? String)
        let node = try Accessibility.select(nodes, needle: needle)!
        guard node.enabled else { throw Failure("The named control is disabled") }
        return node
    }
}
