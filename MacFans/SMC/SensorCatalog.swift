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
    /// Well-known keys for Intel MacBookPro16,1 and similar machines.
    static let known: [SensorDefinition] = [
        .init(id: "TW0P", name: "Airport Proximity", group: .airport, icon: "wifi"),
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
        .init(id: "TG0P", name: "GPU Proximity", group: .gpu, icon: "gpu"),
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
        .init(id: "TH0A", name: "SSD A", group: .drive, icon: "internaldrive"),
        .init(id: "TH0B", name: "SSD B", group: .drive, icon: "internaldrive"),
    ]

    static func definition(for key: String) -> SensorDefinition {
        if let found = known.first(where: { $0.id == key }) {
            return found
        }
        return SensorDefinition(id: key, name: key, group: .other, icon: "thermometer")
    }
}
