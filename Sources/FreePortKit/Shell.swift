import Foundation

enum Shell {
    /// Runs a tool and returns stdout. Never throws on a non-zero exit —
    /// lsof exits 1 whenever any single file can't be stat'ed, which is routine.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 10) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return "" }

        // Read before waiting so a large result can't deadlock on a full pipe buffer.
        let data = out.fileHandleForReading.readDataToEndOfFile()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning { process.terminate() }

        return String(decoding: data, as: UTF8.self)
    }

    static func which(_ name: String) -> String? {
        let known = ["/usr/sbin/\(name)", "/usr/bin/\(name)", "/bin/\(name)",
                     "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        return known.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
