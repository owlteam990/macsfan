import Foundation

struct SensorDefinition: Identifiable, Hashable {
    let id: String          // SMC key
    let name: String
    let group: SensorGroup
    let icon: String

    enum SensorGroup: String, CaseIterable {
        case cpu = "CPU"
        case gpu = "GPU"
        case memory = "内存"
        case battery = "电池"
        case drive = "硬盘"
        case airport = "无线"
        case other = "其他"
    }
}

enum SensorCatalog {
    /// Intel + Apple Silicon 常见温度键（本机探测仍会扫描全部 T*）
    static let known: [SensorDefinition] = [
        // Apple Silicon CPU / efficiency / performance
        .init(id: "Tp01", name: "CPU Performance 1", group: .cpu, icon: "cpu"),
        .init(id: "Tp05", name: "CPU Performance 5", group: .cpu, icon: "cpu"),
        .init(id: "Tp09", name: "CPU Performance 9", group: .cpu, icon: "cpu"),
        .init(id: "Tp0a", name: "CPU Cluster A", group: .cpu, icon: "cpu"),
        .init(id: "Tp0b", name: "CPU Cluster B", group: .cpu, icon: "cpu"),
        .init(id: "Tp0C", name: "CPU Package", group: .cpu, icon: "cpu"),
        .init(id: "Te05", name: "CPU Efficiency 5", group: .cpu, icon: "cpu"),
        .init(id: "Te06", name: "CPU Efficiency 6", group: .cpu, icon: "cpu"),
        .init(id: "TCMb", name: "SoC Max", group: .cpu, icon: "cpu"),
        .init(id: "TCMz", name: "SoC Zone Max", group: .cpu, icon: "cpu"),
        .init(id: "TPDX", name: "CPU Die Max", group: .cpu, icon: "cpu"),

        // Apple Silicon GPU / SSD / wireless
        .init(id: "Tg0P", name: "GPU Proximity", group: .gpu, icon: "gpu"),
        .init(id: "TH0a", name: "SSD A", group: .drive, icon: "internaldrive"),
        .init(id: "TH0b", name: "SSD B", group: .drive, icon: "internaldrive"),
        .init(id: "TH0x", name: "SSD Max", group: .drive, icon: "internaldrive"),
        .init(id: "TW0P", name: "Airport Proximity", group: .airport, icon: "wifi"),

        // Intel MacBookPro16,1 等
        .init(id: "TB0T", name: "Battery Max", group: .battery, icon: "battery.100"),
        .init(id: "TB1T", name: "Battery Sensor 1", group: .battery, icon: "battery.100"),
        .init(id: "TB2T", name: "Battery Sensor 2", group: .battery, icon: "battery.100"),
        .init(id: "TC0C", name: "CPU Core 1", group: .cpu, icon: "cpu"),
        .init(id: "TC1C", name: "CPU Core 2", group: .cpu, icon: "cpu"),
        .init(id: "TC2C", name: "CPU Core 3", group: .cpu, icon: "cpu"),
        .init(id: "TC3C", name: "CPU Core 4", group: .cpu, icon: "cpu"),
        .init(id: "TC4C", name: "CPU Core 5", group: .cpu, icon: "cpu"),
        .init(id: "TC5C", name: "CPU Core 6", group: .cpu, icon: "cpu"),
        .init(id: "TC6C", name: "CPU Core 7", group: .cpu, icon: "cpu"),
        .init(id: "TC7C", name: "CPU Core 8", group: .cpu, icon: "cpu"),
        .init(id: "TC0P", name: "CPU Proximity", group: .cpu, icon: "cpu"),
        .init(id: "TCAD", name: "CPU Package", group: .cpu, icon: "cpu"),
        .init(id: "TCGC", name: "CPU Graphics", group: .gpu, icon: "cpu"),
        .init(id: "TG0D", name: "GPU Diode", group: .gpu, icon: "gpu"),
        .init(id: "TG0P", name: "GPU Proximity (Intel)", group: .gpu, icon: "gpu"),
        .init(id: "TGDD", name: "GPU Die", group: .gpu, icon: "gpu"),
        .init(id: "TG0H", name: "GPU Heatsink", group: .gpu, icon: "gpu"),
        .init(id: "Ts0P", name: "Palm Rest 1", group: .other, icon: "laptopcomputer"),
        .init(id: "Ts1P", name: "Palm Rest 2", group: .other, icon: "laptopcomputer"),
        .init(id: "Th1H", name: "Heatpipe 1", group: .other, icon: "thermometer"),
        .init(id: "Th2H", name: "Heatpipe 2", group: .other, icon: "thermometer"),
        .init(id: "TM0P", name: "Memory Proximity", group: .memory, icon: "memorychip"),
        .init(id: "TPCD", name: "PCH Die", group: .other, icon: "chip"),
        .init(id: "TTRD", name: "Thunderbolt", group: .other, icon: "cable.connector"),
        .init(id: "TH0P", name: "SSD Proximity", group: .drive, icon: "internaldrive"),
        .init(id: "TH0A", name: "SSD A (Intel)", group: .drive, icon: "internaldrive"),
        .init(id: "TH0B", name: "SSD B (Intel)", group: .drive, icon: "internaldrive"),
    ]

    /// 默认曲线传感器：优先 Apple Silicon CPU，再回落到 Intel TC0P
    static let preferredDefaults = [
        "Tp01", "Tp05", "Tp0b", "Tp0a", "Te05", "TCMz", "TCMb", "TPDX", "TC0P", "TCAD"
    ]

    static func definition(for key: String) -> SensorDefinition {
        if let found = known.first(where: { $0.id == key }) {
            return found
        }
        // Apple Silicon 启发式命名
        if key.hasPrefix("Tp") {
            return SensorDefinition(id: key, name: "CPU \(key)", group: .cpu, icon: "cpu")
        }
        if key.hasPrefix("Te") {
            return SensorDefinition(id: key, name: "CPU Eff \(key)", group: .cpu, icon: "cpu")
        }
        if key.hasPrefix("Tg") || key.hasPrefix("TG") {
            return SensorDefinition(id: key, name: "GPU \(key)", group: .gpu, icon: "gpu")
        }
        if key.hasPrefix("TH") || key.hasPrefix("Th") {
            return SensorDefinition(id: key, name: "SSD \(key)", group: .drive, icon: "internaldrive")
        }
        return SensorDefinition(id: key, name: key, group: .other, icon: "thermometer")
    }

    /**
     * 选出本机可用的默认传感器键
     *
     * @param available 已探测到的键列表
     * @return 优先序列中第一个存在的键，否则 available 首个，再否则 "TC0P"
     */
    static func defaultSensorKey(from available: [String]) -> String {
        for key in preferredDefaults where available.contains(key) {
            return key
        }
        return available.first ?? "TC0P"
    }
}
