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
    FanHardwareControl.apply(fanID: fanID, manual: manual, targetRPM: rpm)
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

private var daemonSignalSources: [DispatchSourceSignal] = []
private var daemonShouldStop: Int32 = 0

func installSignalHandlers() {
    // 用 DispatchSource 做退出清理（避免传统 signal handler 里直接碰 IOKit）
    let sigs: [Int32] = [SIGTERM, SIGINT]
    for sig in sigs {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler {
            daemonShouldStop = 1
        }
        source.resume()
        daemonSignalSources.append(source)
    }
}

func runDaemon() {
    installSignalHandlers()

    let controlURL = URL(fileURLWithPath: "/tmp/macfans-control.json")
    let pidURL = URL(fileURLWithPath: "/tmp/macfans-helper.pid")
    try? "\(getpid())".data(using: .utf8)?.write(to: pidURL)

    guard SMC.shared.open() else {
        fputs("daemon: cannot open AppleSMC\n", stderr)
        exit(1)
    }

    // 启动时若上次崩溃留下手动模式，先交还系统再听控制文件
    let fanCount = Int(SMC.shared.readUInt8("FNum") ?? 0)
    if (0..<fanCount).contains(where: FanHardwareControl.isManual) {
        FanHardwareControl.releaseAll(fanCount: fanCount)
    }

    var lastData = Data()
    while daemonShouldStop == 0 {
        autoreleasepool {
            if let data = try? Data(contentsOf: controlURL), data != lastData {
                lastData = data
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let state = (try? decoder.decode(DaemonState.self, from: data))
                    ?? (try? JSONDecoder().decode(DaemonState.self, from: data))
                if let state {
                    for entry in state.fans {
                        _ = writeFan(fanID: entry.id, manual: entry.manual, rpm: entry.targetRPM)
                    }
                }
            }
        }
        Thread.sleep(forTimeInterval: 0.4)
    }

    FanHardwareControl.releaseAll()
    exit(0)
}

let args = CommandLine.arguments
if args.contains("--daemon") {
    runDaemon()
} else {
    runOneShot(args: args)
}
