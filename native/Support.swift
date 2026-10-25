import AppKit
import ApplicationServices
import Foundation

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func encoded(_ value: Any) throws -> String {
    String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!
}

func text(_ args: [String: Any], _ key: String, limit: Int = 2000) throws -> String {
    guard let value = args[key] as? String, !value.isEmpty, value.utf16.count <= limit else { throw Failure("\(key) must contain 1 to \(limit) characters") }
    return value
}

func number(_ args: [String: Any], _ key: String, fallback: Double? = nil) throws -> Double {
    if args[key] == nil, let fallback = fallback { return fallback }
    guard let value = args[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { throw Failure("\(key) must be a finite number") }
    return value.doubleValue
}

func primaryBounds() -> CGRect { CGDisplayBounds(CGMainDisplayID()) }

func point(_ args: [String: Any], _ x: String = "x", _ y: String = "y") throws -> CGPoint {
    let value = CGPoint(x: try number(args, x), y: try number(args, y))
    guard abs(value.x) <= 32767, abs(value.y) <= 32767, primaryBounds().contains(value) else { throw Failure("Point is outside the supported primary display") }
    return value
}

func rectData(_ rect: CGRect) -> [String: Any] {
    ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
}

func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }

func writePrivate(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

func permissions() -> [String: Any] {
    ["accessibility": AXIsProcessTrusted(), "screenRecording": CGPreflightScreenCaptureAccess(), "inputMonitoring": CGPreflightListenEventAccess(), "postEvents": CGPreflightPostEventAccess()]
}

func requireAccessibility() throws {
    guard AXIsProcessTrusted() else { throw Failure("Enable Accessibility for OpenCode Computer Use or its launching terminal in System Settings > Privacy & Security, then restart OpenCode") }
}
