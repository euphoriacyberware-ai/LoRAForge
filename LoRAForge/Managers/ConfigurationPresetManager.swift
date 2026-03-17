import Foundation
import Combine

final class ConfigurationPresetManager: ObservableObject {
    static let shared = ConfigurationPresetManager()

    @Published var presets: [ConfigurationPreset] = []

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LoRAForge")
        self.fileURL = appSupport.appendingPathComponent("configurationPresets.json")
        load()
    }

    // MARK: - CRUD

    func add(_ preset: ConfigurationPreset) {
        presets.append(preset)
        save()
    }

    func update(_ preset: ConfigurationPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        save()
    }

    func delete(id: UUID) {
        presets.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            presets = try decoder.decode([ConfigurationPreset].self, from: data)
        } catch {
            print("Failed to load configuration presets: \(error)")
        }
    }

    func save() {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(presets)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save configuration presets: \(error)")
        }
    }
}
