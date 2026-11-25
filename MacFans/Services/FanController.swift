import Foundation
import Combine

@MainActor
final class FanController: ObservableObject {
    static let shared = FanController()

    @Published var fans: [FanInfo] = []
    @Published var sensors: [SensorReading] = []
    @Published var currentPresetID: UUID = FanPreset.auto.id
    @Published var presets: [FanPreset] = []
    @Published var smcAvailable = false
    @Published var canWrite = false
    @Published var lastError: String?
    @Published var machineModel: String = ""
    @Published var updateInterval: TimeInterval = 1.0
    @Published var launchAtLogin = false
    @Published var showInMenuBar = true

    private var timer: Timer?
    private let presetStore = PresetStore()
    private var discoveredSensorKeys: [String] = []

    private init() {
        machineModel = Self.readModelIdentifier()
        presets = presetStore.load()
        if let saved = UserDefaults.standard.string(forKey: "currentPresetID"),
           let id = UUID(uuidString: saved) {
            currentPresetID = id
        }
        smcAvailable = SMC.shared.open()
        if smcAvailable {
            discoverSensors()
            refreshFansStructure()
            probeWriteAccess()
            // Avoid password prompts on launch; apply when helper/direct write is ready
            if canWrite || ControlChannel.helperRunning {
                applyCurrentPreset(force: true)
            }
            startMonitoring()
        } else {
            lastError = "无法打开 AppleSMC，请确认本机支持 SMC 风扇控制。"
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        refreshReadings()
        applySensorCurves()
    }

    // MARK: - Fans

    private func refreshFansStructure() {
        let count = Int(SMC.shared.readUInt8("FNum") ?? 0)
        var list: [FanInfo] = []
        for i in 0..<count {
            let name = SMC.shared.readString("F\(i)ID") ?? "风扇 \(i + 1)"
            let minRPM = readRPM("F\(i)Mn") ?? 1200
            let maxRPM = readRPM("F\(i)Mx") ?? 6000
            let current = readRPM("F\(i)Ac") ?? 0
            let target = readRPM("F\(i)Tg") ?? current
            // 仅 mode==1 为手动；Apple Silicon 的 mode 3 仍是系统托管
            let manual = FanHardwareControl.isManual(fanID: i)

            var strategy = FanStrategy()
            strategy.fixedRPM = maxRPM
            strategy.sensorKey = SensorCatalog.defaultSensorKey(from: discoveredSensorKeys)
            if manual {
                strategy.mode = .fixed
                strategy.fixedRPM = target
            }

            // Friendly names for MBP 16"
            let displayName: String
            let lower = name.lowercased()
            if lower.contains("left") || i == 0 {
                displayName = count >= 2 ? "左侧风扇" : name
            } else if lower.contains("right") || i == 1 {
                displayName = "右侧风扇"
            } else {
                displayName = name.isEmpty ? "风扇 \(i + 1)" : name
            }

            list.append(FanInfo(
                id: i,
                name: displayName,
                minRPM: minRPM,
                maxRPM: maxRPM,
                currentRPM: current,
                targetRPM: target,
                strategy: strategy,
                isManual: manual
            ))
        }
        fans = list
        ensureBuiltinPresetStrategies()
    }

    private func refreshReadings() {
        for i in fans.indices {
            fans[i].currentRPM = readRPM("F\(i)Ac") ?? fans[i].currentRPM
            fans[i].targetRPM = readRPM("F\(i)Tg") ?? fans[i].targetRPM
            fans[i].isManual = FanHardwareControl.isManual(fanID: i)
        }

        var readings: [SensorReading] = []
        for key in discoveredSensorKeys {
            if let temp = SMC.shared.readNumeric(key), temp > -20, temp < 150 {
                let def = SensorCatalog.definition(for: key)
                readings.append(SensorReading(
                    id: key,
                    name: def.name,
                    temperature: temp,
                    group: def.group,
                    icon: def.icon
                ))
            }
        }

        // Synthetic CPU average
        let cores = readings.filter { $0.name.hasPrefix("CPU Core") && !$0.name.contains("average") }
        if !cores.isEmpty {
            let avg = cores.map(\.temperature).reduce(0, +) / Double(cores.count)
            readings.insert(SensorReading(
                id: "CPUAVG",
                name: "CPU Core (average)",
                temperature: avg,
                group: .cpu,
                icon: "cpu"
            ), at: 0)
        }

        sensors = readings.sorted { a, b in
            if a.group != b.group {
                return a.group.rawValue < b.group.rawValue
            }
            return a.name < b.name
        }
    }

    private func discoverSensors() {
        var keys = Set(SensorCatalog.known.map(\.id))
        // Probe known keys that actually exist
        discoveredSensorKeys = keys.filter { SMC.shared.keyInfo($0) != nil }.sorted()

        // Also scan for temperature-like keys (Txxx)
        let all = SMC.shared.allKeys()
        for key in all where key.count == 4 && key.hasPrefix("T") {
            if SMC.shared.keyInfo(key) != nil {
                if let v = SMC.shared.readNumeric(key), v > 0, v < 120 {
                    discoveredSensorKeys.append(key)
                }
            }
        }
        discoveredSensorKeys = Array(Set(discoveredSensorKeys)).sorted()

        // 用本机可用传感器回填仍指向缺失键的默认曲线
        let fallback = SensorCatalog.defaultSensorKey(from: discoveredSensorKeys)
        for i in fans.indices {
            if SMC.shared.keyInfo(fans[i].strategy.sensorKey) == nil {
                fans[i].strategy.sensorKey = fallback
            }
        }
    }

    private func readRPM(_ key: String) -> Double? {
        if let info = SMC.shared.keyInfo(key) {
            if info.type.trimmingCharacters(in: .whitespaces) == "flt" || info.type == "flt " {
                return SMC.shared.readFLT(key).map(Double.init)
            }
        }
        return SMC.shared.readFPE2(key)
    }

    private func probeWriteAccess() {
        if ControlChannel.helperInstalled || ControlChannel.helperRunning {
            canWrite = true
            return
        }
        guard let fan = fans.first else {
            canWrite = false
            return
        }
        let modeKey = fan.modeKey
        let current = SMC.shared.readUInt8(modeKey) ?? 0
        canWrite = SMC.shared.writeData(modeKey, bytes: [current])
        if !canWrite {
            NSLog("MacFans: direct SMC write unavailable; install helper to control fans")
        }
    }

    private func publishControlState() {
        // Refresh targetRPM for sensor mode before publishing
        for i in fans.indices where fans[i].strategy.mode == .sensor {
            let temp = temperature(for: fans[i].strategy.sensorKey)
            fans[i].targetRPM = fans[i].strategy.rpm(
                forTemperature: temp,
                minRPM: fans[i].minRPM,
                maxRPM: fans[i].maxRPM
            )
        }
        ControlChannel.publish(fans)
    }

    // MARK: - Control

    func setMode(_ mode: FanControlMode, for fanID: Int) {
        guard let idx = fans.firstIndex(where: { $0.id == fanID }) else { return }
        fans[idx].strategy.mode = mode
        applyStrategy(for: fanID)
        syncPresetFromFans()
    }

    func setFixedRPM(_ rpm: Double, for fanID: Int) {
        guard let idx = fans.firstIndex(where: { $0.id == fanID }) else { return }
        let clamped = min(max(rpm, fans[idx].minRPM), fans[idx].maxRPM)
        fans[idx].strategy.mode = .fixed
        fans[idx].strategy.fixedRPM = clamped
        applyStrategy(for: fanID)
        syncPresetFromFans()
    }

    func setSensorStrategy(_ strategy: FanStrategy, for fanID: Int) {
        guard let idx = fans.firstIndex(where: { $0.id == fanID }) else { return }
        fans[idx].strategy = strategy
        fans[idx].strategy.mode = .sensor
        applyStrategy(for: fanID)
        syncPresetFromFans()
    }

    func applyStrategy(for fanID: Int) {
        guard let idx = fans.firstIndex(where: { $0.id == fanID }) else { return }
        let fan = fans[idx]
        switch fan.strategy.mode {
        case .auto:
            fans[idx].isManual = false
        case .fixed:
            fans[idx].isManual = true
            fans[idx].targetRPM = fan.strategy.fixedRPM
        case .sensor:
            fans[idx].isManual = true
            let temp = temperature(for: fan.strategy.sensorKey)
            fans[idx].targetRPM = fan.strategy.rpm(forTemperature: temp, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
        }
        applyToHardware()
    }

    private func applySensorCurves() {
        var changed = false
        for i in fans.indices where fans[i].strategy.mode == .sensor {
            let temp = temperature(for: fans[i].strategy.sensorKey)
            let rpm = fans[i].strategy.rpm(forTemperature: temp, minRPM: fans[i].minRPM, maxRPM: fans[i].maxRPM)
            if abs(fans[i].targetRPM - rpm) > 25 {
                fans[i].targetRPM = rpm
                changed = true
            }
        }
        if changed {
            applyToHardware()
        }
    }

    /// 通过特权助手或进程内 SMC 写入（含 Apple Silicon Ftst 解锁）
    private func applyToHardware() {
        if ControlChannel.helperRunning || ControlChannel.helperInstalled {
            publishControlState()
            canWrite = ControlChannel.helperRunning || ControlChannel.helperInstalled
            return
        }

        var allOK = true
        for fan in fans {
            let manual = fan.strategy.mode != .auto
            let rpm: Double? = manual
                ? (fan.strategy.mode == .fixed ? fan.strategy.fixedRPM : fan.targetRPM)
                : nil
            if !FanHardwareControl.apply(fanID: fan.id, manual: manual, targetRPM: rpm) {
                allOK = false
            }
        }
        canWrite = allOK
        if !allOK {
            // 直写失败时仍发布控制文件，装好助手后由 daemon 生效
            publishControlState()
        }
    }

    private func setManual(_ manual: Bool, fanID: Int) -> Bool {
        if let idx = fans.firstIndex(where: { $0.id == fanID }) {
            fans[idx].isManual = manual
            if !manual { fans[idx].strategy.mode = .auto }
        }
        applyToHardware()
        return canWrite || ControlChannel.helperInstalled
    }

    func temperature(for key: String) -> Double {
        if key == "CPUAVG" {
            return sensors.first(where: { $0.id == "CPUAVG" })?.temperature ?? 50
        }
        return SMC.shared.readNumeric(key)
            ?? sensors.first(where: { $0.id == key })?.temperature
            ?? 50
    }

    // MARK: - Presets (Pro features — free)

    var currentPreset: FanPreset? {
        presets.first(where: { $0.id == currentPresetID })
    }

    func selectPreset(_ preset: FanPreset) {
        currentPresetID = preset.id
        UserDefaults.standard.set(preset.id.uuidString, forKey: "currentPresetID")
        applyCurrentPreset(force: true)
    }

    func applyCurrentPreset(force: Bool = false) {
        guard let preset = currentPreset else { return }

        if preset.id == FanPreset.auto.id {
            for fan in fans {
                _ = setManual(false, fanID: fan.id)
                if let idx = fans.firstIndex(where: { $0.id == fan.id }) {
                    fans[idx].strategy.mode = .auto
                }
            }
            return
        }

        if preset.id == FanPreset.fullSpeed.id {
            for fan in fans {
                var s = FanStrategy()
                s.mode = .fixed
                s.fixedRPM = fan.maxRPM
                if let idx = fans.firstIndex(where: { $0.id == fan.id }) {
                    fans[idx].strategy = s
                }
                applyStrategy(for: fan.id)
            }
            return
        }

        if preset.id == FanPreset.silent.id {
            for fan in fans {
                var s = FanStrategy()
                s.mode = .fixed
                s.fixedRPM = fan.minRPM
                if let idx = fans.firstIndex(where: { $0.id == fan.id }) {
                    fans[idx].strategy = s
                }
                applyStrategy(for: fan.id)
            }
            return
        }

        for (fanID, strategy) in preset.strategies {
            if let idx = fans.firstIndex(where: { $0.id == fanID }) {
                fans[idx].strategy = strategy
                applyStrategy(for: fanID)
            }
        }
    }

    func saveCurrentAsPreset(name: String) {
        var strategies: [Int: FanStrategy] = [:]
        for fan in fans {
            strategies[fan.id] = fan.strategy
        }
        let preset = FanPreset(name: name, strategies: strategies)
        presets.removeAll { $0.name == name && !$0.isBuiltin }
        presets.append(preset)
        presetStore.save(presets)
        selectPreset(preset)
    }

    func updatePreset(_ preset: FanPreset) {
        guard !preset.isBuiltin else { return }
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
            presetStore.save(presets)
            if currentPresetID == preset.id {
                applyCurrentPreset(force: true)
            }
        }
    }

    func deletePreset(_ preset: FanPreset) {
        guard !preset.isBuiltin else { return }
        presets.removeAll { $0.id == preset.id }
        presetStore.save(presets)
        if currentPresetID == preset.id {
            selectPreset(.auto)
        }
    }

    func renamePreset(_ preset: FanPreset, to name: String) {
        guard !preset.isBuiltin, let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx].name = name
        presetStore.save(presets)
    }

    private func syncPresetFromFans() {
        guard let idx = presets.firstIndex(where: { $0.id == currentPresetID }),
              !presets[idx].isBuiltin else { return }
        var strategies: [Int: FanStrategy] = [:]
        for fan in fans {
            strategies[fan.id] = fan.strategy
        }
        presets[idx].strategies = strategies
        presetStore.save(presets)
    }

    private func ensureBuiltinPresetStrategies() {
        var list = presets
        let builtins: [FanPreset] = [.auto, .fullSpeed, .silent]
        for b in builtins where !list.contains(where: { $0.id == b.id }) {
            list.insert(b, at: 0)
        }
        // Keep builtins at front
        list.sort { a, b in
            if a.isBuiltin != b.isBuiltin { return a.isBuiltin && !b.isBuiltin }
            return a.name < b.name
        }
        presets = list
        presetStore.save(presets)
    }

    // MARK: - Privilege helper

    func installPrivilegedHelper() async -> Bool {
        let ok = HelperInstaller.install()
        if ok {
            canWrite = true
            lastError = nil
            applyCurrentPreset(force: true)
        } else {
            lastError = "权限助手安装失败。请确认管理员密码后重试。"
        }
        return ok
    }

    private static func readModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
