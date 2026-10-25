import AppKit
import ApplicationServices
import Darwin

final class IndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ControlSession: NSObject {
    static let shared = ControlSession()
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/opencode-cu-mac", isDirectory: true)
    var owner = ""
    var token = ""
    var ready = false
    var lastTouch = Date()
    var lockDescriptor: Int32 = -1
    var panel: IndicatorPanel?
    var label: NSTextField?
    var timer: Timer?
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var lastPublish = Date.distantPast
    var action = "Ready"
    var stopURL: URL { directory.appendingPathComponent("stop.json") }
    var humanStopURL: URL { directory.appendingPathComponent("human-stop") }
    var stateURL: URL { directory.appendingPathComponent("session.json") }

    func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attrs = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory, (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw Failure("Unsafe control state directory") }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    func publish() throws {
        let value: [String: Any] = ["owner": owner, "token": token, "pid": getpid(), "ready": ready, "updated": Date().timeIntervalSince1970]
        try writePrivate(JSONSerialization.data(withJSONObject: value), to: stateURL)
        lastPublish = Date()
    }

    func monitorEscape() throws {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, _ in
            let session = ControlSession.shared
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { session.stop(human: true); return Unmanaged.passUnretained(event) }
            if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 53 && event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(getpid()) { session.stop(human: true) }
            return Unmanaged.passUnretained(event)
        }, userInfo: nil)
        guard let tap = tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { throw Failure("Escape monitoring is unavailable. Enable Input Monitoring and Accessibility for the helper or launching terminal, then restart") }
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else { throw Failure("Escape monitor did not start") }
    }

    func showPanel() {
        let screen = NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let frame = CGRect(x: screen.midX - 195, y: screen.maxY - 78, width: 390, height: 60)
        let panel = IndicatorPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor(calibratedWhite: 20 / 255, alpha: 1)
        panel.hasShadow = true
        let label = NSTextField(labelWithString: "OpenCode | Starting")
        label.frame = CGRect(x: 14, y: 12, width: 280, height: 38)
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(calibratedRed: 250 / 255, green: 178 / 255, blue: 131 / 255, alpha: 1)
        label.maximumNumberOfLines = 2
        let button = NSButton(title: "Stop", target: self, action: #selector(stopPressed))
        button.frame = CGRect(x: 305, y: 17, width: 70, height: 28)
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("Stop OpenCode desktop control")
        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(button)
        self.panel = panel
        self.label = label
        panel.orderFrontRegardless()
    }

    @objc func stopPressed() { stop(human: true) }

    func checkpoint() throws {
        guard !owner.isEmpty, ready, panel?.isVisible == true, let tap = tap, CGEvent.tapIsEnabled(tap: tap) else { throw Failure("Desktop control stopped; inspect partial input before retrying") }
        guard !FileManager.default.fileExists(atPath: humanStopURL.path) else { stop(); throw Failure("The human stopped control. Ask before manual resume") }
        if matchesStop() { stop(); throw Failure("Desktop control was cancelled") }
    }

    func matchesStop() -> Bool {
        guard let data = try? Data(contentsOf: stopURL), let value = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return false }
        return value["owner"] == owner && value["token"] == token
    }

    func begin(owner requestedOwner: String, seconds: Int) async throws {
        try requireAccessibility()
        guard seconds >= 0 && seconds <= 30, !requestedOwner.isEmpty, requestedOwner.count <= 200 else { throw Failure("Invalid session settings") }
        try prepareDirectory()
        guard !FileManager.default.fileExists(atPath: humanStopURL.path) else { throw Failure("The human stopped control. Ask for permission, then the human can run opencode-cu-mac resume. MCP cannot clear this stop") }
        if !owner.isEmpty {
            guard owner == requestedOwner else { throw Failure("Another client owns desktop control") }
            try checkpoint()
            lastTouch = Date()
            return
        }
        let descriptor = open(directory.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure("Cannot open desktop ownership lock") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); throw Failure("Another computer-use client owns the desktop") }
        lockDescriptor = descriptor
        owner = requestedOwner
        token = UUID().uuidString
        ready = false
        lastTouch = Date()
        do {
            try monitorEscape()
            showPanel()
            try publish()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                let session = ControlSession.shared
                if session.matchesStop() || Date().timeIntervalSince(session.lastTouch) > 60 || session.panel?.isVisible != true { session.stop(); return }
                if Date().timeIntervalSince(session.lastPublish) > 1 { do { try session.publish() } catch { session.stop() } }
            }
            let sessionToken = token
            for remaining in stride(from: seconds, through: 1, by: -1) {
                label?.stringValue = "OpenCode | Starting in \(remaining)s\nEscape or Stop to cancel"
                try await pause(1)
                guard owner == requestedOwner, token == sessionToken, !FileManager.default.fileExists(atPath: humanStopURL.path) else { throw Failure("Control stopped during countdown") }
            }
            guard panel?.isVisible == true, owner == requestedOwner, token == sessionToken else { throw Failure("Control stopped during countdown") }
            ready = true
            label?.stringValue = "OpenCode | Control active\nEscape or Stop to cancel"
            try publish()
        } catch { stop(); throw error }
    }

    func setAction(_ value: String) {
        lastTouch = Date()
        action = value
        label?.stringValue = "OpenCode | \(value)\nEscape or Stop to cancel"
    }

    func stop(human: Bool = false) {
        guard !owner.isEmpty else { return }
        ready = false
        if human { try? writePrivate(Data("Human stopped control\n".utf8), to: humanStopURL) }
        Input.releaseAll()
        timer?.invalidate()
        timer = nil
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
        tapSource = nil
        panel?.close()
        panel = nil
        label = nil
        try? FileManager.default.removeItem(at: stateURL)
        if matchesStop() { try? FileManager.default.removeItem(at: stopURL) }
        owner = ""
        token = ""
        if lockDescriptor >= 0 { flock(lockDescriptor, LOCK_UN); close(lockDescriptor); lockDescriptor = -1 }
    }

    func resume() throws {
        try prepareDirectory()
        guard owner.isEmpty else { throw Failure("Stop active control before resuming") }
        if FileManager.default.fileExists(atPath: humanStopURL.path) { try FileManager.default.removeItem(at: humanStopURL) }
    }
}
