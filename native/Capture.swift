import AppKit
import ScreenCaptureKit
import Vision

enum Capture {
    static func region(_ args: [String: Any]) throws -> CGRect {
        let fields = ["x", "y", "width", "height"].filter { args[$0] != nil }
        if fields.isEmpty { return primaryBounds() }
        guard fields.count == 4 else { throw Failure("Crop requires x, y, width and height") }
        let rect = CGRect(x: try number(args, "x"), y: try number(args, "y"), width: try number(args, "width"), height: try number(args, "height"))
        guard rect.width >= 1, rect.height >= 1, rect.width <= 8192, rect.height <= 8192, primaryBounds().contains(rect) else { throw Failure("Crop must fit the primary display") }
        return rect.integral
    }

    static func image(_ region: CGRect) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw Failure("Enable Screen Recording for OpenCode Computer Use or its launching terminal, then restart OpenCode") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { throw Failure("Primary display is unavailable") }
        let excluded = content.windows.filter { $0.owningApplication?.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        config.sourceRect = region.offsetBy(dx: -primaryBounds().minX, dy: -primaryBounds().minY)
        config.width = Int(region.width)
        config.height = Int(region.height)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func screenshot(_ args: [String: Any]) async throws -> [String: Any] {
        let rect = try region(args)
        let image = try await image(rect)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]), png.count < 8 * 1024 * 1024 else { throw Failure("Capture is too large; use a smaller crop") }
        return ["imageBase64": png.base64EncodedString(), "width": image.width, "height": image.height, "region": rectData(rect), "coordinateSpace": "screen points", "pixelsPerPoint": 1]
    }

    static func ocr(_ args: [String: Any]) async throws -> [String: Any] {
        let rect = try region(args)
        let image = try await image(rect)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let language = args["language"] as? String { request.recognitionLanguages = [language] }
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results ?? []
        var lines: [[String: Any]] = []
        for item in observations.prefix(100) {
            guard let candidate = item.topCandidates(1).first else { continue }
            let box = item.boundingBox
            let location = CGRect(x: rect.minX + box.minX * rect.width, y: rect.minY + (1 - box.maxY) * rect.height, width: box.width * rect.width, height: box.height * rect.height)
            lines.append(["text": String(candidate.string.prefix(500)), "confidence": candidate.confidence, "bounds": rectData(location)])
        }
        return ["lines": lines, "truncated": observations.count > 100, "coordinateSpace": "screen points", "region": rectData(rect)]
    }
}
