import SwiftUI

struct FanRowView: View {
    let fan: FanInfo
    var onSensorControl: () -> Void
    @EnvironmentObject var controller: FanController
    @State private var sliderRPM: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(fan.name)
                    .font(.body.weight(.medium))
                    .frame(width: 90, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(fan.minRPM))  —  \(Int(fan.currentRPM))  —  \(Int(fan.maxRPM))")
                        .monospacedDigit()
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 200)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                strategyButtons
                    .frame(width: 220, alignment: .leading)
            }

            if fan.strategy.mode == .fixed {
                HStack {
                    Text("转速")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $sliderRPM, in: fan.minRPM...fan.maxRPM, step: 50) {
                        Text("RPM")
                    } onEditingChanged: { editing in
                        if !editing {
                            controller.setFixedRPM(sliderRPM, for: fan.id)
                        }
                    }
                    Text("\(Int(sliderRPM))")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.leading, 90)
            }

            if fan.strategy.mode == .sensor {
                HStack {
                    Text("跟随 \(fan.strategy.sensorKey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("编辑曲线…") { onSensorControl() }
                        .controlSize(.small)
                }
                .padding(.leading, 90)
            }
        }
        .padding(.vertical, 6)
        .onAppear { sliderRPM = fan.strategy.fixedRPM > 0 ? fan.strategy.fixedRPM : fan.currentRPM }
        .onChange(of: fan.strategy.fixedRPM) { v in sliderRPM = v }
    }

    private var progress: Double {
        let span = max(1, fan.maxRPM - fan.minRPM)
        return min(1, max(0, (fan.currentRPM - fan.minRPM) / span))
    }

    private var strategyButtons: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                modeButton(.auto, title: "自动")
                modeButton(.fixed, title: "固定转速: \(Int(fan.strategy.mode == .fixed ? fan.strategy.fixedRPM : fan.maxRPM))")
            }
            Button("传感器…") {
                var s = fan.strategy
                s.mode = .sensor
                controller.setSensorStrategy(s, for: fan.id)
                onSensorControl()
            }
            .controlSize(.small)
        }
    }

    private func modeButton(_ mode: FanControlMode, title: String) -> some View {
        let selected = fan.strategy.mode == mode
        return Button(title) {
            if mode == .auto {
                controller.setMode(.auto, for: fan.id)
            } else {
                let rpm = fan.strategy.fixedRPM > 0 ? fan.strategy.fixedRPM : fan.maxRPM
                controller.setFixedRPM(rpm, for: fan.id)
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : nil)
        .disabled(selected && mode == .auto)
    }
}
