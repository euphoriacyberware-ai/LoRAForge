import SwiftUI
import TaggingCore

struct ExportDialogView: View {
    @Binding var document: ProjectDocument
    let bundleURL: URL
    let onChanged: () -> Void

    @Environment(TagRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var baseName: String
    @State private var scope: ExportScope = .finalsOnly
    @State private var result: ExportResult?
    @State private var showingDirectoryPicker = false
    @State private var errorMessage: String?

    init(document: Binding<ProjectDocument>, bundleURL: URL, onChanged: @escaping () -> Void) {
        self._document = document
        self.bundleURL = bundleURL
        self.onChanged = onChanged
        let defaultName = document.wrappedValue.lastExportBaseName
            ?? ExportManager.sanitizeBaseName(document.wrappedValue.name)
        self._baseName = State(initialValue: defaultName)
    }

    private var sanitizedName: String {
        ExportManager.sanitizeBaseName(baseName)
    }

    private var entriesWithFinal: Int {
        document.entries.filter { $0.finalImage != nil }.count
    }

    var body: some View {
        NavigationStack {
            if let result {
                reportView(result)
            } else {
                exportForm
            }
        }
        .frame(minWidth: 420, minHeight: 300)
    }

    // MARK: - Export Form

    private var exportForm: some View {
        Form {
            Section("Export settings") {
                TextField("Base name", text: $baseName)
                Picker("Scope", selection: $scope) {
                    ForEach(ExportScope.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
            }
            Section("Preview") {
                if !sanitizedName.isEmpty {
                    Text("\(sanitizedName)_001.png")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(sanitizedName)_001.txt")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enter a base name")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("\(entriesWithFinal) of \(document.entries.count) entries have a final image and will be exported.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Export")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Export...") { pickDirectory() }
                    .disabled(sanitizedName.isEmpty)
            }
        }
        .alert("Export error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Report

    private func reportView(_ result: ExportResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Export complete")
                .font(.headline)
            Text("\(result.exportedEntries) entr\(result.exportedEntries == 1 ? "y" : "ies") exported, \(result.exportedImages) images, \(result.exportedCaptions) captions.")
            if result.skippedEntries > 0 {
                Text("\(result.skippedEntries) entr\(result.skippedEntries == 1 ? "y" : "ies") skipped (no final image).")
                    .foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Export")
    }

    // MARK: - Actions

    private func pickDirectory() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        panel.message = "Choose a directory for the export"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        performExport(to: url)
        #endif
    }

    private func performExport(to directory: URL) {
        do {
            // Clear existing export if present
            try ExportManager.clearExistingExport(at: directory, baseName: baseName)

            let categories = try repo.allCategories()
            let tags = try repo.allTags()
            let tagDict = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })

            let exportResult = try ExportManager.export(
                document: document,
                bundleURL: bundleURL,
                to: directory,
                baseName: baseName,
                scope: scope,
                categories: categories,
                allTags: tagDict
            )

            // Remember base name
            document.lastExportBaseName = baseName
            onChanged()

            result = exportResult
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
