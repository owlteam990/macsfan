import Foundation

/// Runs FanWriteTool with administrator privileges when direct SMC writes fail.
enum PrivilegedWriter {
    static func toolURL() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "FanWriteTool") {
            return url
        }
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/FanWriteTool")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        // Dev fallback: DerivedData sibling
        let dev = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("FanWriteTool")
        if FileManager.default.isExecutableFile(atPath: dev.path) {
            return dev
        }
        return nil
    }

    @discardableResult
    static func setFan(fanID: Int, manual: Bool, rpm: Double?) -> Bool {
        guard let tool = toolURL() else {
            NSLog("MacFans: FanWriteTool not found")
            return false
        }

        var parts = [
            quoted(tool.path),
            "--fan", "\(fanID)",
            "--manual", manual ? "1" : "0"
        ]
        if let rpm {
            parts += ["--rpm", "\(Int(rpm.rounded()))"]
        }
        let command = parts.joined(separator: " ")
        let script = "do shell script \(appleScriptString(command)) with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let err = Pipe()
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                NSLog("MacFans: privileged write failed: \(msg)")
            }
            return process.terminationStatus == 0
        } catch {
            NSLog("MacFans: privileged write error: \(error)")
            return false
        }
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
