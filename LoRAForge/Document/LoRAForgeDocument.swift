import SwiftUI
import Combine
import UniformTypeIdentifiers

final class LoRAForgeDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.loraForgeProject] }
    static var writableContentTypes: [UTType] { [.loraForgeProject] }

    @Published var metadata: ProjectMetadata
    @Published var schema: SchemaSnapshot

    struct Snapshot {
        let metadata: ProjectMetadata
        let schema: SchemaSnapshot
    }

    // New document
    init() {
        self.metadata = ProjectMetadata()
        self.schema = SchemaSnapshot()
    }

    // Open from file
    required init(configuration: ReadConfiguration) throws {
        guard configuration.file.isDirectory,
              let wrappers = configuration.file.fileWrappers else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()

        guard let metaData = wrappers["project.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.metadata = try decoder.decode(ProjectMetadata.self, from: metaData)

        guard let schemaData = wrappers["schema.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.schema = try decoder.decode(SchemaSnapshot.self, from: schemaData)
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        Snapshot(metadata: metadata, schema: schema)
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let directory = FileWrapper(directoryWithFileWrappers: [:])

        let metaData = try encoder.encode(snapshot.metadata)
        directory.addRegularFile(withContents: metaData, preferredFilename: "project.json")

        let schemaData = try encoder.encode(snapshot.schema)
        directory.addRegularFile(withContents: schemaData, preferredFilename: "schema.json")

        // Preserve existing wrappers for entries/images (Phase 5+)
        if let existing = configuration.existingFile?.fileWrappers {
            for (key, wrapper) in existing where key != "project.json" && key != "schema.json" {
                directory.addFileWrapper(wrapper)
            }
        }

        return directory
    }
}
