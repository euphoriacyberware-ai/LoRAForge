import SwiftUI
import SwiftData
import TaggingCore

struct ReconciliationView: View {
    let result: ReconciliationResult
    @ObservedObject var document: LoRAForgeDocument
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var importedCategoryIDs: Set<UUID> = []
    @State private var importedTagIDs: Set<UUID> = []
    @State private var importError: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            List {
                if !result.missingCategories.isEmpty {
                    Section("Missing categories") {
                        ForEach(result.missingCategories) { cat in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(cat.name)
                                    if let prefix = cat.prefix {
                                        Text("prefix: \(prefix)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if importedCategoryIDs.contains(cat.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Import") { importCategory(cat) }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                if !result.missingTags.isEmpty {
                    Section("Missing tags") {
                        ForEach(result.missingTags) { tag in
                            HStack {
                                Text(tag.canonicalString)
                                Spacer()
                                if importedTagIDs.contains(tag.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Import") { importTag(tag) }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                if !result.driftedCategories.isEmpty {
                    Section("Changed since last save") {
                        ForEach(result.driftedCategories, id: \.snapshot.id) { drift in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(drift.snapshot.name)
                                if drift.prefixChanged {
                                    Text("Prefix: \"\(drift.snapshot.prefix ?? "none")\" → \"\(drift.current.prefix ?? "none")\"")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                if drift.selectModeChanged {
                                    Text("Select mode changed")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Project reconciliation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import all") { importAll() }
                        .disabled(allImported)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Import error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var allImported: Bool {
        result.missingCategories.allSatisfy { importedCategoryIDs.contains($0.id) }
            && result.missingTags.allSatisfy { importedTagIDs.contains($0.id) }
    }

    private func importCategory(_ cat: CategorySnapshot) {
        let service = ReconciliationService(modelContext: modelContext)
        do {
            try service.importCategory(cat)
            importedCategoryIDs.insert(cat.id)
        } catch {
            importError = "Failed to import '\(cat.name)': \(error.localizedDescription)"
            showError = true
        }
    }

    private func importTag(_ tag: TagSnapshot) {
        let service = ReconciliationService(modelContext: modelContext)
        do {
            let result = try service.importTag(tag)
            switch result {
            case .created, .mappedToExisting:
                importedTagIDs.insert(tag.id)
            case .nearMatchesFound:
                // For now, create anyway — Phase 6 can refine the near-match UI
                let tagRepo = SwiftDataTagRepository(modelContext: modelContext)
                _ = try tagRepo.createTag(
                    canonicalString: tag.canonicalString,
                    inCategory: tag.categoryID
                )
                importedTagIDs.insert(tag.id)
            }
        } catch {
            importError = "Failed to import '\(tag.canonicalString)': \(error.localizedDescription)"
            showError = true
        }
    }

    private func importAll() {
        for cat in result.missingCategories where !importedCategoryIDs.contains(cat.id) {
            importCategory(cat)
        }
        for tag in result.missingTags where !importedTagIDs.contains(tag.id) {
            importTag(tag)
        }
    }
}
