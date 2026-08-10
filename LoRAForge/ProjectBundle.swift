import Foundation

struct ProjectBundle {
    let url: URL

    private var projectURL: URL { url.appending(path: "project.json") }
    private var schemaURL: URL { url.appending(path: "schema.json") }
    private var imagesURL: URL { url.appending(path: "images") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Create

    static func create(at url: URL, project: ProjectDocument, schema: SchemaSnapshot) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: url.appending(path: "images"),
            withIntermediateDirectories: true
        )

        let bundle = ProjectBundle(url: url)
        try bundle.writeProjectAtomic(project)
        try bundle.writeSchemaAtomic(schema)
    }

    // MARK: - Read

    func readProject() throws -> ProjectDocument {
        let data = try Data(contentsOf: projectURL)
        return try Self.decoder.decode(ProjectDocument.self, from: data)
    }

    func readSchema() throws -> SchemaSnapshot {
        let data = try Data(contentsOf: schemaURL)
        return try Self.decoder.decode(SchemaSnapshot.self, from: data)
    }

    // MARK: - Atomic Write

    func writeProjectAtomic(_ doc: ProjectDocument) throws {
        try writeAtomic(Self.encoder.encode(doc), to: projectURL)
    }

    func writeSchemaAtomic(_ snapshot: SchemaSnapshot) throws {
        try writeAtomic(Self.encoder.encode(snapshot), to: schemaURL)
    }

    private func writeAtomic(_ data: Data, to destination: URL) throws {
        let temp = destination.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).tmp")
        try data.write(to: temp, options: .atomic)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: destination)
        }
    }
}
