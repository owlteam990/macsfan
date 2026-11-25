import SwiftUI

struct SensorControlEditor: View {
    @EnvironmentObject var controller: FanController
    @Environment(\.dismiss) private var dismiss

    let fan: FanInfo
    @State private var strategy: FanStrategy
    @State private var selectedSensor: String

    init(fan: FanInfo) {
        self.fan = fan
        _strategy = State(initialValue: {
            var s = fan.strategy
            s.mode = .sensor
            return s
        }())
        _selectedSensor = State(initialValue: fan.strategy.sensorKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("传感器控制 — \(fan.name)")
                .font(.title2.weight(.semibold))

            Text("根据选定传感器温度，按曲线自动调节转速。此功能在商业软件中通常为 Pro 付费项，本应用免费提供。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("传感器", selection: $selectedSensor) {
                ForEach(controller.sensors) { s in
                    Text("\(s.name) (\(Int(s.temperature))°C)").tag(s.id)
                }
            }

            Text("温度 — 转速曲线")
                .font(.headline)

            List {
                ForEach($strategy.curve) { $point in
                    HStack {
                        Text("温度")
                        Slider(value: $point.temperature, in: 20...100, step: 1)
                        Text("\(Int(point.temperature))°C")
                            .frame(width: 48, alignment: .trailing)
                            .monospacedDigit()
                        Text("转速")
                        Slider(value: $point.rpm, in: fan.minRPM...fan.maxRPM, step: 50)
                        Text("\(Int(point.rpm))")
                            .frame(width: 56, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
                .onDelete { strategy.curve.remove(atOffsets: $0) }
            }
            .frame(minHeight: 180)

            HStack {
                Button("添加节点") {
                    strategy.curve.append(CurvePoint(temperature: 60, rpm: (fan.minRPM + fan.maxRPM) / 2))
                }
                Spacer()
                let temp = controller.temperature(for: selectedSensor)
                let preview = strategy.rpm(forTemperature: temp, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
                Text("当前 \(Int(temp))°C → \(Int(preview)) RPM")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("应用") {
                    strategy.sensorKey = selectedSensor
                    strategy.mode = .sensor
                    controller.setSensorStrategy(strategy, for: fan.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
