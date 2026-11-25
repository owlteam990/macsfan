import Foundation

enum FanControlMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case fixed
    case sensor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .fixed: return "固定转速"
        case .sensor: return "传感器控制"
        }
    }
}

struct CurvePoint: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var temperature: Double  // °C
    var rpm: Double
}

struct FanStrategy: Codable, Hashable {
    var mode: FanControlMode = .auto
    var fixedRPM: Double = 0
    /// Sensor SMC key used when mode == .sensor（启动后按本机可用键回填）
    var sensorKey: String = "Tp01"
    /// Temperature → RPM curve (sorted by temperature)
    var curve: [CurvePoint] = [
        CurvePoint(temperature: 40, rpm: 2000),
        CurvePoint(temperature: 55, rpm: 3000),
        CurvePoint(temperature: 70, rpm: 4500),
        CurvePoint(temperature: 85, rpm: 5500)
    ]

    func rpm(forTemperature temp: Double, minRPM: Double, maxRPM: Double) -> Double {
        let sorted = curve.sorted { $0.temperature < $1.temperature }
        guard let first = sorted.first, let last = sorted.last else {
            return minRPM
        }
        if temp <= first.temperature { return clamp(first.rpm, minRPM, maxRPM) }
        if temp >= last.temperature { return clamp(last.rpm, minRPM, maxRPM) }

        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]
            if temp >= a.temperature && temp <= b.temperature {
                let t = (temp - a.temperature) / max(0.001, b.temperature - a.temperature)
                let rpm = a.rpm + (b.rpm - a.rpm) * t
                return clamp(rpm, minRPM, maxRPM)
            }
        }
        return clamp(last.rpm, minRPM, maxRPM)
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}

struct FanInfo: Identifiable, Hashable {
    let id: Int
    var name: String
    var minRPM: Double
    var maxRPM: Double
    var currentRPM: Double
    var targetRPM: Double
    var strategy: FanStrategy
    var isManual: Bool

    var speedKey: String { "F\(id)Ac" }
    var minKey: String { "F\(id)Mn" }
    var maxKey: String { "F\(id)Mx" }
    var targetKey: String { "F\(id)Tg" }
    /// 运行时解析：优先 `F{n}Md`，否则 `F{n}md`（M5）
    var modeKey: String { FanHardwareControl.modeKey(for: id) ?? "F\(id)Md" }
    var idKey: String { "F\(id)ID" }
}

struct SensorReading: Identifiable, Hashable {
    let id: String
    var name: String
    var temperature: Double
    var group: SensorDefinition.SensorGroup
    var icon: String
}

struct FanPreset: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// fanIndex → strategy
    var strategies: [Int: FanStrategy]
    var createdAt: Date = Date()
    var isBuiltin: Bool = false

    static let auto = FanPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "自动",
        strategies: [:],
        isBuiltin: true
    )

    static let fullSpeed = FanPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "全速",
        strategies: [:],
        isBuiltin: true
    )

    static let silent = FanPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "静音",
        strategies: [:],
        isBuiltin: true
    )
}

extension FanPreset: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, strategies, createdAt, isBuiltin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isBuiltin = try c.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
        let raw = try c.decodeIfPresent([String: FanStrategy].self, forKey: .strategies) ?? [:]
        strategies = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in
            Int(k).map { ($0, v) }
        })
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isBuiltin, forKey: .isBuiltin)
        let raw = Dictionary(uniqueKeysWithValues: strategies.map { (String($0.key), $0.value) })
        try c.encode(raw, forKey: .strategies)
    }
}
