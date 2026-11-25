import SwiftUI

struct PresetManagerView: View {
    @EnvironmentObject var controller: FanController
    @Environment(\.dismiss) private var dismiss
    @State private var renameTarget: FanPreset?
    @State private var renameText = ""
    @State private var newName = ""
    @State private var showRename = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            presetList
            createRow
            Button("完成") { dismiss() }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .alert("重命名预设", isPresented: $showRename) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let p = renameTarget {
                    controller.renamePreset(p, to: renameText)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("预设管理")
                .font(.title2.weight(.semibold))
            Text("创建、保存并快速切换自定义风扇预设 — 全部免费，无序列号。")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var presetList: some View {
        List {
            ForEach(controller.presets) { preset in
                PresetRow(
                    preset: preset,
                    isActive: preset.id == controller.currentPresetID,
                    onApply: { controller.selectPreset(preset) },
                    onRename: {
                        renameTarget = preset
                        renameText = preset.name
                        showRename = true
                    },
                    onDelete: { controller.deletePreset(preset) }
                )
            }
        }
    }

    private var createRow: some View {
        HStack {
            TextField("新预设名称", text: $newName)
            Button("从当前配置创建") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                controller.saveCurrentAsPreset(name: name)
                newName = ""
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

private struct PresetRow: View {
    let preset: FanPreset
    let isActive: Bool
    let onApply: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.body.weight(isActive ? .bold : .regular))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
            Button("应用", action: onApply)
                .controlSize(.small)
            if !preset.isBuiltin {
                Button("重命名", action: onRename)
                    .controlSize(.small)
                Button("删除", role: .destructive, action: onDelete)
                    .controlSize(.small)
            }
        }
    }

    private var subtitle: String {
        if preset.isBuiltin {
            return "内置"
        }
        return "自定义 · \(preset.strategies.count) 个风扇策略"
    }
}
