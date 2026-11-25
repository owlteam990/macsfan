import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: FanController
    @State private var showPresetManager = false
    @State private var showSensorControl: FanInfo?
    @State private var showSavePreset = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                fanPanel
                    .frame(minWidth: 420)
                Divider()
                sensorPanel
                    .frame(minWidth: 300)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showPresetManager) {
            PresetManagerView()
                .environmentObject(controller)
                .frame(width: 560, height: 420)
        }
        .sheet(item: $showSensorControl) { fan in
            SensorControlEditor(fan: fan)
                .environmentObject(controller)
                .frame(width: 520, height: 480)
        }
        .alert("保存为预设", isPresented: $showSavePreset) {
            TextField("预设名称", text: $newPresetName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let name = newPresetName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                controller.saveCurrentAsPreset(name: name)
                newPresetName = ""
            }
        } message: {
            Text("自定义预设可随时切换，无需付费。")
        }
        .alert("提示", isPresented: Binding(
            get: { controller.lastError != nil },
            set: { if !$0 { controller.lastError = nil } }
        )) {
            Button("好") { controller.lastError = nil }
        } message: {
            Text(controller.lastError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("当前预设:")
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { controller.currentPresetID },
                set: { id in
                    if let p = controller.presets.first(where: { $0.id == id }) {
                        controller.selectPreset(p)
                    }
                }
            )) {
                ForEach(controller.presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .labelsHidden()
            .frame(width: 160)

            Button {
                showPresetManager = true
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("管理预设（免费 Pro 功能）")

            Button("保存当前…") {
                newPresetName = ""
                showSavePreset = true
            }

            Spacer()

            Text(controller.machineModel)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var fanPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("风扇")
                    .frame(width: 90, alignment: .leading)
                Text("最低 / 当前 / 最大")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("控制策略")
                    .frame(width: 220, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            if controller.fans.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "fanblades")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(controller.smcAvailable ? "未检测到风扇" : "SMC 不可用")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(controller.fans) { fan in
                        FanRowView(fan: fan) {
                            showSensorControl = fan
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var sensorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("传感器")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("°C")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            List(controller.sensors) { sensor in
                HStack(spacing: 8) {
                    Image(systemName: sensor.icon)
                        .foregroundStyle(tempColor(sensor.temperature))
                        .frame(width: 18)
                    Text(sensor.name)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f", sensor.temperature))
                        .monospacedDigit()
                        .foregroundStyle(tempColor(sensor.temperature))
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            if controller.canWrite {
                Label("已可控制风扇", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Label("控制风扇需安装权限助手（仅一次）", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Button("安装权限助手…") {
                    Task {
                        _ = await controller.installPrivilegedHelper()
                    }
                }
                .controlSize(.small)
            }

            Spacer()

            Button("设置…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func tempColor(_ t: Double) -> Color {
        switch t {
        case ..<50: return .secondary
        case 50..<70: return .primary
        case 70..<85: return .orange
        default: return .red
        }
    }
}
