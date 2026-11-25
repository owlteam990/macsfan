import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var controller: FanController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MacFans")
                .font(.headline)
            Text(controller.machineModel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(controller.fans) { fan in
                Text("\(fan.name): \(Int(fan.currentRPM)) RPM")
                    .monospacedDigit()
            }

            if let cpu = controller.sensors.first(where: { $0.id == "CPUAVG" }) {
                Text("CPU 均温: \(Int(cpu.temperature))°C")
                    .monospacedDigit()
            }

            Divider()

            Menu("预设: \(controller.currentPreset?.name ?? "—")") {
                ForEach(controller.presets) { preset in
                    Button(preset.name) {
                        controller.selectPreset(preset)
                    }
                }
            }

            Divider()

            Button("打开主窗口") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
            }

            Button("退出") {
                // Restore auto before quit
                controller.selectPreset(.auto)
                NSApp.terminate(nil)
            }
        }
        .padding(4)
    }
}
