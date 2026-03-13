import Foundation
import Combine

final class TemplateManager: ObservableObject {
    static let shared = TemplateManager()

    @Published var templates: [Template] = []

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LoRAForge")
        self.fileURL = appSupport.appendingPathComponent("templates.json")
        load()
    }

    // MARK: - CRUD

    func add(_ template: Template) {
        templates.append(template)
        save()
    }

    func update(_ template: Template) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        save()
    }

    func delete(id: UUID) {
        templates.removeAll { $0.id == id }
        save()
    }

    // MARK: - Import / Export

    func exportTemplate(_ template: Template, to url: URL) throws {
        let envelope = TemplateExportEnvelope(version: TemplateExportEnvelope.currentVersion, template: template)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    func importTemplate(from url: URL) throws -> Template {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(TemplateExportEnvelope.self, from: data)

        guard envelope.version <= TemplateExportEnvelope.currentVersion else {
            throw TemplateImportError.unsupportedVersion(envelope.version)
        }

        var imported = envelope.template
        imported.id = UUID()
        imported.prompts = imported.prompts.map { prompt in
            var p = prompt
            p.id = UUID()
            return p
        }

        add(imported)
        return imported
    }

    enum TemplateImportError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "This template file requires a newer version of LoRAForge (file version \(v))."
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            templates = try decoder.decode([Template].self, from: data)
        } catch {
            print("Failed to load templates: \(error)")
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
            let data = try encoder.encode(templates)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save templates: \(error)")
        }
    }
}
