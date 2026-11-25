import Foundation

/// Shared control file between the UI app and the root LaunchDaemon.
struct FanControlState: Codable {
    var fans: [FanControlEntry]
    var updatedAt: Date

    struct FanControlEntry: Codable {
        var id: Int
        var manual: Bool
        var targetRPM: Double?
    }
}

enum ControlChannel {
    /// World-readable path so the root daemon can pick it up.
    static var controlURL: URL {
        URL(fileURLWithPath: "/tmp/macfans-control.json")
    }

    static var pidURL: URL {
        URL(fileURLWithPath: "/tmp/macfans-helper.pid")
    }

    static func publish(_ fans: [FanInfo]) {
        let entries: [FanControlState.FanControlEntry] = fans.map { fan in
            let manual = fan.strategy.mode != .auto
            let rpm: Double?
            switch fan.strategy.mode {
            case .auto: rpm = nil
            case .fixed: rpm = fan.strategy.fixedRPM
            case .sensor: rpm = fan.targetRPM
            }
            return FanControlState.FanControlEntry(id: fan.id, manual: manual, targetRPM: rpm)
        }
        publishExplicit(entries: entries)
    }

    static func publishExplicit(entries: [FanControlState.FanControlEntry]) {
        let state = FanControlState(fans: entries, updatedAt: Date())
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: controlURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: controlURL.path)
        } catch {
            NSLog("MacFans: failed to publish control state: \(error)")
        }
    }

    static var helperInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.macfans.helper.plist")
            && FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/com.macfans.FanWriteTool")
    }

    /// Root daemons cannot be signaled by a normal user (`kill` → EPERM).
    /// EPERM still means the process exists; only ESRCH means it is gone.
    static var helperRunning: Bool {
        if let data = try? Data(contentsOf: pidURL),
           let text = String(data: data, encoding: .utf8),
           let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid > 1 {
            let rc = kill(pid, 0)
            if rc == 0 { return true }
            if errno == EPERM { return true }
        }
        // Fallback: ask launchd (works without signaling the root pid)
        return launchdSaysRunning()
    }

    private static func launchdSaysRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/com.macfans.helper"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return text.contains("state = running") || text.contains("pid = ")
        } catch {
            return false
        }
    }
}
