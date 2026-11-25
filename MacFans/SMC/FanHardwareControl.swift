import Foundation

/// 风扇硬件写入（Intel + Apple Silicon）。
///
/// Apple Silicon（尤其 M3/M4）：`thermalmonitord` 常把风扇置于 mode 3（System），
/// 固件拒绝 `F*Md=1`，需先写诊断键 `Ftst=1` 并重试；部分机型（如部分 M4 mini / M5）
/// 无 `Ftst`，root 下可直接写模式键。M5 模式键可能为小写 `F*md`。
/// Intel：可用 `FS! ` 位掩码，或直接写 `F*Md`。
enum FanHardwareControl {

    /// 风扇模式：0=自动，1=手动，3=系统托管（Apple Silicon）
    enum Mode: UInt8 {
        case automatic = 0
        case manual = 1
        case system = 3
    }

    private static let testKey = "Ftst"
    private static let intelForceKey = "FS! "
    private static let unlockTimeout: TimeInterval = 10
    private static let unlockRetryInterval: TimeInterval = 0.1

    /// 解析本机实际存在的模式键（`F0Md` 或 `F0md`）
    static func modeKey(for fanID: Int) -> String? {
        let upper = "F\(fanID)Md"
        if SMC.shared.keyExists(upper) {
            return upper
        }
        let lower = "F\(fanID)md"
        if SMC.shared.keyExists(lower) {
            return lower
        }
        return nil
    }

    static var hasTestFlag: Bool {
        SMC.shared.keyExists(testKey)
    }

    static var hasIntelForceMask: Bool {
        SMC.shared.keyExists(intelForceKey)
    }

    /// 读取模式；仅 `1` 视为手动
    static func readMode(fanID: Int) -> Mode? {
        guard let key = modeKey(for: fanID),
              let raw = SMC.shared.readUInt8(key) else {
            return nil
        }
        return Mode(rawValue: raw) ?? .system
    }

    static func isManual(fanID: Int) -> Bool {
        if hasIntelForceMask {
            let mask = Int(SMC.shared.readUInt8(intelForceKey) ?? 0)
            return ((mask >> fanID) & 1) == 1
        }
        return readMode(fanID: fanID) == .manual
    }

    /// 将风扇设为手动并写入目标转速；必要时执行 `Ftst` 解锁。
    @discardableResult
    static func engage(fanID: Int, targetRPM: Double?) -> Bool {
        guard SMC.shared.open() else {
            return false
        }

        // 1. Intel FS! 路径
        if hasIntelForceMask {
            let mask = Int(SMC.shared.readUInt8(intelForceKey) ?? 0)
            let newMask = UInt8(mask | (1 << fanID))
            guard SMC.shared.writeData(intelForceKey, bytes: [newMask]) else {
                return false
            }
            if let rpm = targetRPM {
                return writeTarget(fanID: fanID, rpm: rpm)
            }
            return true
        }

        guard let modeKey = modeKey(for: fanID) else {
            return false
        }

        // 2. 已是手动则只更新目标转速
        if readMode(fanID: fanID) == .manual {
            if let rpm = targetRPM {
                return writeTarget(fanID: fanID, rpm: rpm)
            }
            return true
        }

        // 3. 先尝试直接写手动模式（M1 / 部分 M4 mini / M5）
        var modeResult: UInt8 = 0xFF
        if writeMode(modeKey, .manual, result: &modeResult) {
            if let rpm = targetRPM {
                return writeTarget(fanID: fanID, rpm: rpm)
            }
            return true
        }

        // 无 root 时 IOKit 直接拒绝，提示装助手即可
        if modeResult == 0xFF && geteuid() != 0 {
            NSLog("MacFans: SMC write needs root (fan %d); install helper", fanID)
            return false
        }

        // 4. M3/M4：Ftst 解锁后重试
        guard hasTestFlag else {
            NSLog("MacFans: mode write refused (result=0x%02x) and Ftst absent (fan %d)", modeResult, fanID)
            return false
        }

        guard setTestFlag(true) else {
            NSLog("MacFans: failed to set Ftst")
            return false
        }

        let started = Date()
        while Date().timeIntervalSince(started) < unlockTimeout {
            if writeMode(modeKey, .manual) {
                NSLog("MacFans: fan %d manual after %.1fs", fanID, Date().timeIntervalSince(started))
                if let rpm = targetRPM {
                    return writeTarget(fanID: fanID, rpm: rpm)
                }
                return true
            }
            Thread.sleep(forTimeInterval: unlockRetryInterval)
        }

        NSLog("MacFans: unlock timeout for fan %d", fanID)
        // 若没有任何手动风扇，清掉 Ftst
        if !anyManualFan() {
            _ = setTestFlag(false)
        }
        return false
    }

    /// 交还系统自动控制；无手动风扇时清除 `Ftst`。
    @discardableResult
    static func release(fanID: Int) -> Bool {
        guard SMC.shared.open() else {
            return false
        }

        if hasIntelForceMask {
            let mask = Int(SMC.shared.readUInt8(intelForceKey) ?? 0)
            let newMask = UInt8(mask & ~(1 << fanID))
            return SMC.shared.writeData(intelForceKey, bytes: [newMask])
        }

        guard let modeKey = modeKey(for: fanID) else {
            return false
        }
        let mode = readMode(fanID: fanID)
        if mode == .automatic || mode == .system {
            if !anyManualFanExcept(fanID) {
                _ = setTestFlag(false)
            }
            return true
        }

        let ok = writeMode(modeKey, .automatic)
        if !anyManualFanExcept(fanID) {
            _ = setTestFlag(false)
        }
        return ok
    }

    /// 统一入口：manual=false 释放；manual=true 接管并设转速。
    @discardableResult
    static func apply(fanID: Int, manual: Bool, targetRPM: Double?) -> Bool {
        if manual {
            return engage(fanID: fanID, targetRPM: targetRPM)
        }
        return release(fanID: fanID)
    }

    /// 应用退出 / helper 停止前：全部交还系统。
    static func releaseAll(fanCount: Int? = nil) {
        let count = fanCount ?? Int(SMC.shared.readUInt8("FNum") ?? 0)
        for i in 0..<count {
            _ = release(fanID: i)
        }
        _ = setTestFlag(false)
    }

    // MARK: - Private

    private static func writeMode(_ key: String, _ mode: Mode, result: inout UInt8) -> Bool {
        let ok = SMC.shared.writeDataEx(key, bytes: [mode.rawValue], result: &result)
        if ok && (result == 0 || result == UInt8(kSMCResultKeySizeMismatch)) {
            return true
        }
        // IOKit 失败（无权限）或固件 0x82
        return false
    }

    private static func writeMode(_ key: String, _ mode: Mode) -> Bool {
        var result: UInt8 = 0xFF
        return writeMode(key, mode, result: &result)
    }

    @discardableResult
    private static func setTestFlag(_ on: Bool) -> Bool {
        guard hasTestFlag else {
            return !on
        }
        for _ in 0..<20 {
            var result: UInt8 = 0xFF
            if SMC.shared.writeDataEx(testKey, bytes: [on ? 1 : 0], result: &result),
               result == 0 || result == UInt8(kSMCResultKeySizeMismatch) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private static func writeTarget(fanID: Int, rpm: Double) -> Bool {
        let key = "F\(fanID)Tg"
        let clamped = max(0, rpm)
        for _ in 0..<10 {
            var ok = false
            if let info = SMC.shared.keyInfo(key) {
                let t = info.type.trimmingCharacters(in: .whitespaces).lowercased()
                if t == "flt" {
                    ok = SMC.shared.writeFLT(key, value: Float(clamped))
                } else {
                    ok = SMC.shared.writeFPE2(key, value: clamped)
                }
            } else {
                ok = SMC.shared.writeFLT(key, value: Float(clamped))
                    || SMC.shared.writeFPE2(key, value: clamped)
            }
            if ok {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private static func anyManualFan() -> Bool {
        let count = Int(SMC.shared.readUInt8("FNum") ?? 0)
        return (0..<count).contains { isManual(fanID: $0) }
    }

    private static func anyManualFanExcept(_ fanID: Int) -> Bool {
        let count = Int(SMC.shared.readUInt8("FNum") ?? 0)
        return (0..<count).contains { $0 != fanID && isManual(fanID: $0) }
    }
}
