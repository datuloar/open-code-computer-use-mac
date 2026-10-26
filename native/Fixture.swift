import AppKit

final class DesktopFixture: NSObject, NSTextViewDelegate {
    let folder: URL
    var window: NSWindow!
    var editor: NSTextView!
    init(folder: String) { self.folder = URL(fileURLWithPath: folder, isDirectory: true) }
    func start() throws {
        window = NSWindow(contentRect: CGRect(x: 150, y: 150, width: 680, height: 430), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "OpenCode Mac Test \(getpid())"
        let title = NSTextField(labelWithString: "OpenCode computer-use test workspace")
        title.frame = CGRect(x: 24, y: 380, width: 620, height: 25)
        window.contentView?.addSubview(title)
        let scroll = NSScrollView(frame: CGRect(x: 24, y: 110, width: 632, height: 250))
        editor = NSTextView(frame: scroll.bounds)
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.setAccessibilityLabel("Test editor")
        editor.setAccessibilitySubrole(.unknown)
        editor.setAccessibilityEnabled(true)
        editor.delegate = self
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        window.contentView?.addSubview(scroll)
        let button = NSButton(title: "Test action", target: self, action: #selector(clicked))
        button.frame = CGRect(x: 24, y: 38, width: 180, height: 40)
        button.bezelStyle = .rounded
        window.contentView?.addSubview(button)
        let password = NSSecureTextField(frame: CGRect(x: 230, y: 44, width: 250, height: 28))
        password.setAccessibilityLabel("Test password")
        password.stringValue = "fixture-secret-only"
        window.contentView?.addSubview(password)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try writePrivate(JSONSerialization.data(withJSONObject: ["pid": getpid(), "title": window.title]), to: folder.appendingPathComponent("ready.json"))
    }
    @objc func clicked() { try? writePrivate(Data("clicked".utf8), to: folder.appendingPathComponent("clicked.txt")) }
    func textDidChange(_ notification: Notification) { try? writePrivate(Data(editor.string.utf8), to: folder.appendingPathComponent("text.txt")) }
}
