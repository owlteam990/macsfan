import Foundation

/// Swift wrapper around AppleSMC bridge.
final class SMC {
    static let shared = SMC()

    private var connection: io_connect_t = 0
    private let lock = NSLock()

    var isOpen: Bool { connection != 0 }

    @discardableResult
    func open() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 { return true }
        return smc_open(&connection)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 {
            smc_close(connection)
            connection = 0
        }
    }

    static func fourCC(_ string: String) -> UInt32 {
        string.withCString { smc_fourcc($0) }
    }

    static func keyString(_ key: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((key >> 24) & 0xFF),
            UInt8((key >> 16) & 0xFF),
            UInt8((key >> 8) & 0xFF),
            UInt8(key & 0xFF)
        ]
        return String(bytes: bytes.filter { $0 >= 32 && $0 < 127 }, encoding: .ascii) ?? ""
    }

    func keyInfo(_ key: String) -> (size: UInt32, type: String)? {
        guard open() else { return nil }
        lock.lock()
        defer { lock.unlock() }

        var size: UInt32 = 0
        var type: UInt32 = 0
        guard smc_get_key_info(connection, Self.fourCC(key), &size, &type) else { return nil }
        return (size, Self.keyString(type))
    }

    func readData(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard open() else { return nil }
        lock.lock()
        defer { lock.unlock() }

        var size: UInt32 = 32
        var type: UInt32 = 0
        var buffer = [UInt8](repeating: 0, count: 32)
        guard smc_read_key(connection, Self.fourCC(key), &buffer, &size, &type) else { return nil }
        return (Self.keyString(type), Array(buffer.prefix(Int(size))))
    }

    func writeData(_ key: String, bytes: [UInt8]) -> Bool {
        guard open() else { return false }
        lock.lock()
        defer { lock.unlock() }

        return bytes.withUnsafeBufferPointer { ptr in
            smc_write_key(connection, Self.fourCC(key), ptr.baseAddress, UInt32(bytes.count))
        }
    }

    func readUInt8(_ key: String) -> UInt8? {
        guard let data = readData(key), !data.bytes.isEmpty else { return nil }
        return data.bytes[0]
    }

    func readUInt16(_ key: String) -> UInt16? {
        guard let data = readData(key), data.bytes.count >= 2 else { return nil }
        return (UInt16(data.bytes[0]) << 8) | UInt16(data.bytes[1])
    }

    func readUInt32(_ key: String) -> UInt32? {
        guard let data = readData(key), data.bytes.count >= 4 else { return nil }
        return (UInt32(data.bytes[0]) << 24)
            | (UInt32(data.bytes[1]) << 16)
            | (UInt32(data.bytes[2]) << 8)
            | UInt32(data.bytes[3])
    }

    /// FPE2: RPM encoded as value * 4
    func readFPE2(_ key: String) -> Double? {
        guard let raw = readUInt16(key) else { return nil }
        return Double(raw) / 4.0
    }

    func writeFPE2(_ key: String, value: Double) -> Bool {
        let scaled = UInt16(max(0, min(value, 65535.0 / 4.0)) * 4.0)
        return writeData(key, bytes: [UInt8((scaled >> 8) & 0xFF), UInt8(scaled & 0xFF)])
    }

    /// SP78 temperature
    func readSP78(_ key: String) -> Double? {
        guard let data = readData(key), data.bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: (UInt16(data.bytes[0]) << 8) | UInt16(data.bytes[1]))
        return Double(raw) / 256.0
    }

    func readFLT(_ key: String) -> Float? {
        guard let data = readData(key), data.bytes.count >= 4 else { return nil }
        var bits: UInt32 = 0
        bits |= UInt32(data.bytes[0])
        bits |= UInt32(data.bytes[1]) << 8
        bits |= UInt32(data.bytes[2]) << 16
        bits |= UInt32(data.bytes[3]) << 24
        return Float(bitPattern: bits)
    }

    func writeFLT(_ key: String, value: Float) -> Bool {
        let bits = value.bitPattern
        return writeData(key, bytes: [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF)
        ])
    }

    func readNumeric(_ key: String) -> Double? {
        guard let data = readData(key) else { return nil }
        switch data.type {
        case "sp78", "SP78":
            return readSP78(key)
        case "fpe2", "FPE2":
            return readFPE2(key)
        case "flt ", "FLT ":
            return readFLT(key).map(Double.init)
        case "ui8 ", "UI8 ":
            return data.bytes.first.map(Double.init)
        case "ui16", "UI16":
            return readUInt16(key).map(Double.init)
        case "ui32", "UI32":
            return readUInt32(key).map(Double.init)
        default:
            if data.bytes.count >= 2 { return readSP78(key) }
            if let b = data.bytes.first { return Double(b) }
            return nil
        }
    }

    func readString(_ key: String) -> String? {
        guard let data = readData(key) else { return nil }
        let cleaned = data.bytes.filter { $0 >= 32 && $0 < 127 }
        return String(bytes: cleaned, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func allKeys(limit: Int = 800) -> [String] {
        guard let count = readUInt32("#KEY") else { return [] }
        var keys: [String] = []
        lock.lock()
        defer { lock.unlock() }
        guard connection != 0 else { return [] }
        for i in 0..<min(Int(count), limit) {
            var key: UInt32 = 0
            if smc_key_at_index(connection, UInt32(i), &key) {
                let s = Self.keyString(key)
                if !s.isEmpty { keys.append(s) }
            }
        }
        return keys
    }
}
