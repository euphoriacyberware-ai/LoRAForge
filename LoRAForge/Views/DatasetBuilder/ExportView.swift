import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExportView: View {
    @ObservedObject var document: LoRAForgeDocument
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var baseName: String = ""
    @State private var scope: ExportScope = .finalsOnly
    @State private var showDirectoryPicker = false
    @State private var clearFirst = true
    @State private var exportReport: ExportReport?
    @State private var showReport = false
    @State private var exportError: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Base name") {
                    TextField("Base name", text: $baseName)
                    if !baseName.isEmpty {
                        LabeledContent("Preview") {
                            Text(previewFilename)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !isValidBaseName {
                        Text("Name must contain at least one alphanumeric character.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Scope") {
                    Picker("Export scope", selection: $scope) {
                        ForEach(ExportScope.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Text("Discarded images are never exported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Clear previous export first", isOn: $clearFirst)
                } footer: {
                    Text("Removes files matching this base name from the destination before exporting.")
                }

                Section {
                    LabeledContent("Entries with finals") {
                        Text("\(entriesWithFinals) of \(document.entries.count)")
                    }
                    if entriesWithoutFinals > 0 {
                        Text("\(entriesWithoutFinals) entries have no final image and will be skipped.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export...") { showDirectoryPicker = true }
                        .disabled(!isValidBaseName)
                }
            }
            .onAppear {
                if baseName.isEmpty {
                    baseName = document.metadata.exportBaseName
                        ?? sanitizeForDefault(document.metadata.name)
                }
            }
            .fileExporter(
                isPresented: $showDirectoryPicker,
                document: ExportDirectoryDocument(),
                contentType: .folder,
                defaultFilename: baseName
            ) { result in
                // fileExporter for folders doesn't work well; fall back to fileImporter
            }
            // Use fileImporter to select a directory instead
            .fileImporter(
                isPresented: $showDirectoryPicker,
                allowedContentTypes: [.folder]
            ) { result in
                switch result {
                case .success(let url):
                    performExport(to: url)
                case .failure(let error):
                    exportError = error.localizedDescription
                    showError = true
                }
            }
            .alert("Export complete", isPresented: $showReport) {
                Button("OK") { dismiss() }
            } message: {
                if let report = exportReport {
                    Text("\(report.exported) of \(report.exported + report.skipped) entries exported.\n\(report.totalImages) images, \(report.totalSidecars) sidecars.\(report.skippedNoFinal > 0 ? "\n\(report.skippedNoFinal) entries skipped (no final image)." : "")")
                }
            }
            .alert("Export failed", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(exportError ?? "Unknown error")
            }
        }
    }

    // MARK: - Computed

    private var previewFilename: String {
        let sanitized = sanitizeBaseName(baseName)
        return "\(sanitized)_001.png, \(sanitized)_001.txt"
    }

    private var isValidBaseName: Bool {
        !sanitizeBaseName(baseName).isEmpty
    }

    private var entriesWithFinals: Int {
        document.entries.filter { $0.finalImage != nil }.count
    }

    private var entriesWithoutFinals: Int {
        document.entries.count - entriesWithFinals
    }

    // MARK: - Actions

    private func performExport(to url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            exportError = "Could not access the selected directory."
            showError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Remember base name
        document.metadata.exportBaseName = baseName

        let service = ExportService(document: document, modelContext: modelContext)
        do {
            let report = try service.export(
                to: url,
                baseName: baseName,
                scope: scope,
                clearFirst: clearFirst
            )
            exportReport = report
            showReport = true
        } catch {
            exportError = error.localizedDescription
            showError = true
        }
    }

    private func sanitizeBaseName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(name.unicodeScalars.filter { allowed.contains($0) })
    }

    private func sanitizeForDefault(_ name: String) -> String {
        let sanitized = sanitizeBaseName(name)
        return sanitized.isEmpty ? "export" : sanitized
    }
}

/// Placeholder document type so fileExporter compiles — we use fileImporter for directories instead.
struct ExportDirectoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    init() {}
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: [:])
    }
}
