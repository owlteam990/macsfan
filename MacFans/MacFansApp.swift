import SwiftUI

@main
struct MacFansApp: App {
    @StateObject private var controller = FanController.shared
    @State private var showMainWindow = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 780, minHeight: 420)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("预设") {
                ForEach(controller.presets) { preset in
                    Button(preset.name) {
                        controller.selectPreset(preset)
                    }
                }
            }
        }

        MenuBarExtra("MacFans", systemImage: "fanblades") {
            MenuBarView()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(controller)
        }
    }
}
