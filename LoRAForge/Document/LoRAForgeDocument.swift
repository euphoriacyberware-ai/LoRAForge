import SwiftUI
import Combine
import UniformTypeIdentifiers

final class LoRAForgeDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.loraForgeProject] }
    static var writableContentTypes: [UTType] { [.loraForgeProject] }

    @Published var metadata: ProjectMetadata
    @Published var schema: SchemaSnapshot
    @Published var entries: [DatasetEntry]
    var imagesWrapper: FileWrapper

    struct Snapshot {
        let metadata: ProjectMetadata
        let schema: SchemaSnapshot
        let entries: [DatasetEntry]
        let imagesWrapper: FileWrapper
    }

    // MARK: - Init

    init() {
        self.metadata = ProjectMetadata()
        self.schema = SchemaSnapshot()
        self.entries = []
        self.imagesWrapper = FileWrapper(directoryWithFileWrappers: [:])
    }

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

        if let entriesData = wrappers["entries.json"]?.regularFileContents {
            self.entries = try decoder.decode([DatasetEntry].self, from: entriesData)
        } else {
            self.entries = []
        }

        self.imagesWrapper = wrappers["images"] ?? FileWrapper(directoryWithFileWrappers: [:])
    }

    // MARK: - Save

    func snapshot(contentType: UTType) throws -> Snapshot {
        // Deep-copy the images wrapper so the snapshot is independent
        let imgCopy = FileWrapper(directoryWithFileWrappers: [:])
        if let wrappers = imagesWrapper.fileWrappers {
            for (key, wrapper) in wrappers {
                if let data = wrapper.regularFileContents {
                    imgCopy.addRegularFile(withContents: data, preferredFilename: key)
                }
            }
        }
        return Snapshot(metadata: metadata, schema: schema,
                        entries: entries, imagesWrapper: imgCopy)
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let directory = FileWrapper(directoryWithFileWrappers: [:])

        let metaData = try encoder.encode(snapshot.metadata)
        directory.addRegularFile(withContents: metaData, preferredFilename: "project.json")

        let schemaData = try encoder.encode(snapshot.schema)
        directory.addRegularFile(withContents: schemaData, preferredFilename: "schema.json")

        let entriesData = try encoder.encode(snapshot.entries)
        directory.addRegularFile(withContents: entriesData, preferredFilename: "entries.json")

        let imgDir = snapshot.imagesWrapper
        imgDir.preferredFilename = "images"
        directory.addFileWrapper(imgDir)

        return directory
    }

    // MARK: - Image helpers

    func imageData(for filename: String) -> Data? {
        imagesWrapper.fileWrappers?[filename]?.regularFileContents
    }

    func addImage(data: Data, extension ext: String, to entryID: UUID) {
        let filename = "\(UUID().uuidString).\(ext.isEmpty ? "png" : ext)"
        imagesWrapper.addRegularFile(withContents: data, preferredFilename: filename)
        if let idx = entries.firstIndex(where: { $0.id == entryID }) {
            entries[idx].images.append(EntryImage(filename: filename))
        }
    }

    func removeImageFile(_ filename: String) {
        if let wrapper = imagesWrapper.fileWrappers?[filename] {
            imagesWrapper.removeFileWrapper(wrapper)
        }
    }
}
