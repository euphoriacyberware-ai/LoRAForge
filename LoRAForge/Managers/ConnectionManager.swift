import Foundation
import Combine

final class ConnectionManager: ObservableObject {
    static let shared = ConnectionManager()

    @Published var connections: [ServerConnection] = []

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LoRAForge")
        self.fileURL = appSupport.appendingPathComponent("connections.json")
        load()
    }

    // MARK: - CRUD

    func add(_ connection: ServerConnection) {
        connections.append(connection)
        save()
    }

    func update(_ connection: ServerConnection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
        save()
    }

    func delete(id: UUID) {
        connections.removeAll { $0.id == id }
        save()
    }

    // MARK: - Filtered Access

    func connections(ofType type: ConnectionType) -> [ServerConnection] {
        connections.filter { $0.type == type }
    }

    func connection(for id: UUID?) -> ServerConnection? {
        guard let id else { return nil }
        return connections.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            connections = try JSONDecoder().decode([ServerConnection].self, from: data)
        } catch {
            print("Failed to load connections: \(error)")
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
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(connections)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save connections: \(error)")
        }
    }
}
