import Foundation

/// FanWriteTool dual mode:
/// 1) One-shot: --fan N --manual 0|1 [--rpm RPM]
/// 2) Daemon:   --daemon   (poll /tmp/macfans-control.json and apply as root)

private struct DaemonState: Codable {
    struct Entry: Codable {
        var id: Int
        var manual: Bool
        var targetRPM: Double?
    }
    var fans: [Entry]
    var updatedAt: Date
}

func writeFan(fanID: Int, manual: Bool, rpm: Double?) -> Bool {
    guard SMC.shared.open() else { return false }
    let modeOK = SMC.shared.writeData("F\(fanID)Md", bytes: [manual ? 1 : 0])
    var rpmOK = true
    if let rpm, manual {
        let key = "F\(fanID)Tg"
        if let info = SMC.shared.keyInfo(key),
           info.type.trimmingCharacters(in: .whitespaces).lowercased() == "flt" {
            rpmOK = SMC.shared.writeFLT(key, value: Float(rpm))
        } else {
            rpmOK = SMC.shared.writeFPE2(key, value: rpm)
        }
    }
    return modeOK && rpmOK
}

func runOneShot(args: [String]) {
    func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    guard let fanStr = value("--fan"), let fanID = Int(fanStr) else {
        fputs("usage: FanWriteTool --fan N --manual 0|1 [--rpm RPM]\n       FanWriteTool --daemon\n", stderr)
        exit(2)
    }
    let manual = (Int(value("--manual") ?? "1") ?? 1) != 0
    let rpm = value("--rpm").flatMap(Double.init)
    exit(writeFan(fanID: fanID, manual: manual, rpm: rpm) ? 0 : 1)
}

func runDaemon() {
    let controlURL = URL(fileURLWithPath: "/tmp/macfans-control.json")
    let pidURL = URL(fileURLWithPath: "/tmp/macfans-helper.pid")
    try? "\(getpid())".data(using: .utf8)?.write(to: pidURL)

    guard SMC.shared.open() else {
        fputs("daemon: cannot open AppleSMC\n", stderr)
        exit(1)
    }

    var lastData = Data()
    while true {
        autoreleasepool {
            if let data = try? Data(contentsOf: controlURL), data != lastData {
                lastData = data
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let state = try? decoder.decode(DaemonState.self, from: data) {
                    for entry in state.fans {
                        _ = writeFan(fanID: entry.id, manual: entry.manual, rpm: entry.targetRPM)
                    }
                } else if let state = try? JSONDecoder().decode(DaemonState.self, from: data) {
                    for entry in state.fans {
                        _ = writeFan(fanID: entry.id, manual: entry.manual, rpm: entry.targetRPM)
                    }
                }
            }
        }
        Thread.sleep(forTimeInterval: 0.4)
    }
}

let args = CommandLine.arguments
if args.contains("--daemon") {
    runDaemon()
} else {
    runOneShot(args: args)
}
