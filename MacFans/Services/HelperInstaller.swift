import Foundation

enum HelperInstaller {
    static let plistPath = "/Library/LaunchDaemons/com.macfans.helper.plist"
    static let toolInstallPath = "/Library/PrivilegedHelperTools/com.macfans.FanWriteTool"

    static func install() -> Bool {
        guard let tool = PrivilegedWriter.toolURL() else {
            NSLog("MacFans: bundled FanWriteTool missing")
            return false
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.macfans.helper</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(toolInstallPath)</string>
                <string>--daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/tmp/macfans-helper.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/macfans-helper.err</string>
        </dict>
        </plist>
        """

        let tmpPlist = "/tmp/com.macfans.helper.plist"
        do {
            try plist.write(toFile: tmpPlist, atomically: true, encoding: .utf8)
        } catch {
            return false
        }

        // Copy tool + install launchd as root (one password prompt)
        let script = """
        do shell script "mkdir -p /Library/PrivilegedHelperTools && \
        cp -f '\(tool.path)' '\(toolInstallPath)' && \
        chown root:wheel '\(toolInstallPath)' && \
        chmod 755 '\(toolInstallPath)' && \
        cp -f '\(tmpPlist)' '\(plistPath)' && \
        chown root:wheel '\(plistPath)' && \
        chmod 644 '\(plistPath)' && \
        launchctl bootout system '\(plistPath)' 2>/dev/null; \
        launchctl bootstrap system '\(plistPath)' && \
        launchctl enable system/com.macfans.helper && \
        launchctl kickstart -k system/com.macfans.helper" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let err = Pipe()
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
            let errMsg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                NSLog("MacFans: helper install failed: \(errMsg)")
                // osascript may still have installed files before a later launchctl step failed
            }

            // Wait for launchd to spawn the daemon
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 0.25)
                if ControlChannel.helperInstalled && ControlChannel.helperRunning {
                    return true
                }
            }
            // Files present = install OK even if process check lags
            if ControlChannel.helperInstalled {
                NSLog("MacFans: helper files installed; launchd may still be starting (\(errMsg))")
                return true
            }
            return false
        } catch {
            return false
        }
    }

    static func uninstall() -> Bool {
        let script = """
        do shell script "launchctl bootout system '\(plistPath)' 2>/dev/null; \
        rm -f '\(plistPath)' '\(toolInstallPath)' /tmp/macfans-helper.pid /tmp/macfans-control.json" with administrator privileges
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
