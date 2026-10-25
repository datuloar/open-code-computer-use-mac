import AppKit
import ApplicationServices
import Darwin

enum Checks {
    static func require(_ value: Bool, _ message: String) throws {
        guard value else { throw Failure(message) }
    }

    static func rejects(_ message: String, _ action: () throws -> Void) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        try require(rejected, message)
    }

    static func run() throws -> [String] {
        let cmd = try Input.keys("cmd+shift+a")
        try require(cmd.0.count == 2 && cmd.1 == 0 && cmd.2.contains(.maskCommand) && cmd.2.contains(.maskShift), "Key mapping failed")
        try rejects("Invalid keys must fail") { _ = try Input.keys("cmd+unknown") }
        try rejects("Duplicate modifiers must fail") { _ = try Input.keys("cmd+command+a") }
        try rejects("Boolean coordinates must fail") { _ = try number(["x": true], "x") }
        try rejects("Nonfinite coordinates must fail") { _ = try number(["x": Double.infinity], "x") }
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let data = try JSONSerialization.data(withJSONObject: rectData(rect))
        let restored = try JSONSerialization.jsonObject(with: data) as! [String: Double]
        try require(restored == ["x": 10, "y": 20, "width": 30, "height": 40], "Geometry JSON round trip failed")

        let element = AXUIElementCreateApplication(getpid())
        func node(_ name: String, enabled: Bool) -> Accessibility.Node {
            Accessibility.Node(element: element, name: name, identifier: "", role: "AXButton", bounds: rect, enabled: enabled, depth: 1)
        }
        let disabled = node("Save", enabled: false)
        let substring = node("Save as", enabled: true)
        let selected = try Accessibility.select([disabled, substring], needle: "Save")
        try require(selected?.name == "Save" && selected?.enabled == false, "Disabled exact match redirected input")
        let enabled = node("Save", enabled: true)
        try require(try Accessibility.select([disabled, enabled], needle: "Save")?.enabled == true, "Enabled exact match must win")
        try rejects("Ambiguous controls must fail") { _ = try Accessibility.select([enabled, enabled], needle: "Save") }
        try require(try Accessibility.select([], needle: "Save", optional: true) == nil, "Missing controls must remain missing")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("opencode-mac-native-check-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = ControlSession(directory: folder.appendingPathComponent("state", isDirectory: true))
        try session.prepareDirectory()
        try writePrivate(Data("Human stopped control\n".utf8), to: session.humanStopURL)
        let descriptor = open(session.directory.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure("Test lock could not open") }
        defer { close(descriptor) }
        try require(flock(descriptor, LOCK_EX | LOCK_NB) == 0, "Test lock could not acquire")
        try rejects("Resume must not clear a stop during another session") { try session.resume() }
        try require(FileManager.default.fileExists(atPath: session.humanStopURL.path), "Resume removed a live stop")
        flock(descriptor, LOCK_UN)
        try session.resume()
        try require(!FileManager.default.fileExists(atPath: session.humanStopURL.path), "Manual resume did not clear stop")
        let link = folder.appendingPathComponent("linked-state")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: session.directory)
        try rejects("Symlink state directories must fail") { try ControlSession(directory: link).prepareDirectory() }
        return ["modifier mapping", "invalid input", "geometry JSON", "exact and ambiguous control matching", "resume ownership lock", "private state paths", "native framework linkage"]
    }
}
