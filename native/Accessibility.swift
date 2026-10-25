import AppKit
import ApplicationServices

enum Accessibility {
    struct Node {
        let element: AXUIElement
        let name: String
        let identifier: String
        let role: String
        let bounds: CGRect
        let enabled: Bool
        let depth: Int
        var data: [String: Any] { ["name": name, "id": identifier, "role": role, "bounds": rectData(bounds), "x": bounds.midX, "y": bounds.midY, "enabled": enabled, "depth": depth] }
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String { attribute(element, name) as? String ?? "" }
    static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] { attribute(element, name) as? [AXUIElement] ?? [] }

    static func element(_ source: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(source, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func bounds(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func app(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        return app
    }

    static func target(_ args: [String: Any], allowMinimized: Bool = false) throws -> AXUIElement {
        try requireAccessibility()
        guard args["pid"] == nil || args["window"] == nil else { throw Failure("Use pid or window, not both") }
        var selected: AXUIElement?
        if let title = args["window"] as? String {
            guard !title.isEmpty else { throw Failure("Window title must not be empty") }
            var matches: [AXUIElement] = []
            for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
                for window in elements(app(running.processIdentifier), kAXWindowsAttribute) {
                    if string(window, kAXTitleAttribute).localizedCaseInsensitiveContains(title) { matches.append(window) }
                }
            }
            guard matches.count == 1 else { throw Failure("Expected one window matching that title; found \(matches.count)") }
            selected = matches[0]
        } else {
            let identifier = try number(args, "pid", fallback: Double(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0))
            guard identifier > 0, identifier <= Double(Int32.max), identifier.rounded() == identifier else { throw Failure("Invalid target pid") }
            let application = app(pid_t(identifier))
            selected = element(application, kAXFocusedWindowAttribute)
            if selected == nil {
                let windows = elements(application, kAXWindowsAttribute)
                guard windows.count == 1 else { throw Failure("The app has no unique focused window; use an observed title") }
                selected = windows[0]
            }
        }
        guard let window = selected else { throw Failure("No target window") }
        if !allowMinimized, attribute(window, kAXMinimizedAttribute) as? Bool == true { throw Failure("Window is minimized; focus it first") }
        return window
    }

    static func collect(_ window: AXUIElement, depth: Int = 14, cap: Int = 1600) throws -> [Node] {
        var nodes: [Node] = []
        var visited: [AXUIElement] = []
        var count = 0
        func visit(_ element: AXUIElement, _ level: Int) throws {
            guard level <= depth else { return }
            if visited.contains(where: { CFEqual($0, element) }) { return }
            visited.append(element)
            count += 1
            if count > cap { throw Failure("Accessibility tree exceeds its bound; narrow the target window or use a fresh crop") }
            let role = string(element, kAXRoleAttribute)
            if let rect = bounds(element), rect.intersects(primaryBounds()) {
                let title = string(element, kAXTitleAttribute)
                let description = string(element, kAXDescriptionAttribute)
                let label = title.isEmpty ? description : title
                let identifier = string(element, kAXIdentifierAttribute)
                nodes.append(Node(element: element, name: String(label.prefix(200)), identifier: String(identifier.prefix(200)), role: role, bounds: rect, enabled: attribute(element, kAXEnabledAttribute) as? Bool ?? false, depth: level))
            }
            for child in elements(element, kAXChildrenAttribute) { try visit(child, level + 1) }
        }
        try visit(window, 0)
        return nodes
    }

    static func matches(_ nodes: [Node], needle: String, role: String?) -> [Node] {
        nodes.filter { node in
            (role == nil || node.role.caseInsensitiveCompare(role!) == .orderedSame) &&
            (node.name.localizedCaseInsensitiveContains(needle) || node.identifier.localizedCaseInsensitiveContains(needle))
        }
    }

    static func select(_ nodes: [Node], needle: String, optional: Bool = false) throws -> Node? {
        if nodes.isEmpty {
            if optional { return nil }
            throw Failure("No matching control")
        }
        let exact = nodes.filter { $0.name.caseInsensitiveCompare(needle) == .orderedSame || $0.identifier.caseInsensitiveCompare(needle) == .orderedSame }
        let shortlist = exact.isEmpty ? nodes : exact
        let enabled = shortlist.filter { $0.enabled }
        let candidates = enabled.isEmpty ? shortlist : enabled
        guard candidates.count == 1 else { throw Failure("\(candidates.count) controls match; use an observed AX role, a more specific label, or a fresh crop") }
        return candidates[0]
    }

    static func inspect(_ node: Node?, limit: Int) -> [String: Any] {
        guard let node = node else { return ["found": false] }
        var output: [String: Any] = ["found": true, "control": node.data, "value": NSNull(), "valueStatus": "unavailable", "truncated": false]
        guard let subrole = attribute(node.element, kAXSubroleAttribute) as? String, !subrole.isEmpty else { return output }
        if subrole == kAXSecureTextFieldSubrole as String { output["valueStatus"] = "protected"; return output }
        guard let value = attribute(node.element, kAXValueAttribute) else { return output }
        if let value = value as? String {
            output["value"] = String(value.prefix(limit))
            output["valueStatus"] = "available"
            output["truncated"] = value.count > limit
        } else if let value = value as? NSNumber {
            output["value"] = value
            output["valueStatus"] = "available"
        }
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(node.element, kAXValueAttribute as CFString, &settable) == .success { output["readOnly"] = !settable.boolValue }
        return output
    }

    static func verifyHit(_ node: Node) throws {
        guard node.enabled else { throw Failure("The named control is disabled") }
        let location = CGPoint(x: node.bounds.midX, y: node.bounds.midY)
        guard primaryBounds().contains(location) else { throw Failure("The control is outside the primary display") }
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(location.x), Float(location.y), &hit)
        guard result == .success else { throw Failure("Cannot verify the control under the pointer") }
        var current = hit
        for _ in 0..<32 {
            guard let item = current else { break }
            if CFEqual(item, node.element) { return }
            current = element(item, kAXParentAttribute)
        }
        throw Failure("The control is covered or its Accessibility identity cannot be verified; refresh the target")
    }

    static func focus(_ window: AXUIElement) throws {
        var identifier: pid_t = 0
        guard AXUIElementGetPid(window, &identifier) == .success, let application = NSRunningApplication(processIdentifier: identifier) else { throw Failure("Target application disappeared") }
        if attribute(window, kAXMinimizedAttribute) as? Bool == true {
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else { throw Failure("Cannot restore minimized window") }
        }
        application.activate(options: [.activateIgnoringOtherApps])
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else { throw Failure("Cannot raise the target window") }
    }
}
