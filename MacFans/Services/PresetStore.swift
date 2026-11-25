import Foundation

final class PresetStore {
    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacFans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("presets.json")
    }

    func load() -> [FanPreset] {
        guard let data = try? Data(contentsOf: url) else {
            return [.auto, .fullSpeed, .silent]
        }
        do {
            var presets = try JSONDecoder().decode([FanPreset].self, from: data)
            let builtins: [FanPreset] = [.auto, .fullSpeed, .silent]
            for b in builtins where !presets.contains(where: { $0.id == b.id }) {
                presets.insert(b, at: 0)
            }
            return presets
        } catch {
            return [.auto, .fullSpeed, .silent]
        }
    }

    func save(_ presets: [FanPreset]) {
        do {
            let data = try JSONEncoder().encode(presets)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Failed to save presets: \(error)")
        }
    }
}
