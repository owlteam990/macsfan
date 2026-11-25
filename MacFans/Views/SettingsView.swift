import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var controller: FanController

    var body: some View {
        Form {
            Section("监控") {
                Picker("刷新间隔", selection: $controller.updateInterval) {
                    Text("0.5 秒").tag(0.5)
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                }
                .onChange(of: controller.updateInterval) { _ in
                    controller.startMonitoring()
                }
            }

            Section("启动") {
                Toggle("登录时启动", isOn: $controller.launchAtLogin)
                    .onChange(of: controller.launchAtLogin) { enabled in
                        setLaunchAtLogin(enabled)
                    }
            }

            Section("关于") {
                LabeledContent("版本", value: "1.0.0")
                LabeledContent("机型", value: controller.machineModel)
                Text("免费开源风扇控制，包含自定义预设与传感器曲线（商业 Pro 功能）。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 280)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            controller.lastError = "设置登录启动失败: \(error.localizedDescription)"
        }
    }
}
