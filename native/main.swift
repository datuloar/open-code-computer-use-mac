import AppKit
import Darwin

let end = "\u{001e}OPENCODE-CU-END"
func output(_ value: String) { FileHandle.standardOutput.write(Data((value + "\n").utf8)) }

if CommandLine.arguments.contains("--check") {
    do {
        output(try encoded(["passed": true, "checks": try Checks.run()]))
        exit(0)
    } catch { output(error.localizedDescription); exit(1) }
}

let application = NSApplication.shared
application.setActivationPolicy(CommandLine.arguments.contains("--fixture") ? .regular : .accessory)
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
func quit() { ControlSession.shared.stop(); NSApp.terminate(nil) }
term.setEventHandler { quit() }
interrupt.setEventHandler { quit() }
term.resume()
interrupt.resume()
var fixture: DesktopFixture?
if let index = CommandLine.arguments.firstIndex(of: "--fixture"), CommandLine.arguments.count > index + 1 {
    fixture = DesktopFixture(folder: CommandLine.arguments[index + 1])
    do { try fixture!.start() } catch { output(error.localizedDescription); exit(1) }
} else {
    guard CommandLine.arguments.contains("--serve") else { output("Use the Node CLI or --serve"); exit(1) }
    output(end + " READY")
    DispatchQueue.global(qos: .userInitiated).async {
        while let line = readLine() {
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                Task { @MainActor in
                    do {
                        guard line.utf8.count <= 32768, let data = line.data(using: .utf8), let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure("Invalid request frame") }
                        let result = try await Dispatcher.run(request)
                        output(try encoded(result))
                        output(end + " 0")
                    } catch {
                        Input.releaseAll()
                        output("ERROR " + error.localizedDescription.replacingOccurrences(of: "\n", with: " "))
                        output(end + " 1")
                    }
                    done.signal()
                }
            }
            done.wait()
        }
        DispatchQueue.main.async { quit() }
    }
}
application.run()
