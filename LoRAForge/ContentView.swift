import SwiftUI
import SwiftData
import TaggingCore

struct ContentView: View {
    @ObservedObject var document: LoRAForgeDocument
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = AppTab.datasetBuilder
    @State private var reconciliationResult: ReconciliationResult?
    @State private var showReconciliation = false
    @State private var initialized = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dataset builder", systemImage: "square.grid.2x2", value: .datasetBuilder) {
                DatasetBuilderView(document: document)
            }
            Tab("Reference library", systemImage: "photo.on.rectangle", value: .referenceLibrary) {
                ReferenceLibraryView()
            }
            Tab("Tag library", systemImage: "tag", value: .tagLibrary) {
                TagLibraryView()
            }
        }
        .task { setUp() }
        .sheet(isPresented: $showReconciliation) {
            if let result = reconciliationResult {
                ReconciliationView(result: result, document: document)
            }
        }
    }

    private func setUp() {
        guard !initialized else { return }
        initialized = true

        // Populate new documents with current library state
        if document.metadata.categoryOrder.isEmpty {
            let catRepo = SwiftDataCategoryRepository(modelContext: modelContext)
            let categories = (try? catRepo.allCategories()) ?? []
            document.metadata = ProjectMetadata(
                id: document.metadata.id,
                name: document.metadata.name,
                categoryOrder: categories.map(\.id),
                disabledCategories: Set(categories.filter { !$0.isEnabled }.map(\.id))
            )
            document.schema = SchemaSnapshot(
                tags: [],
                categories: categories.map { CategorySnapshot(from: $0) }
            )
        }

        // Register as known project
        let projectRepo = SwiftDataKnownProjectsRepository(modelContext: modelContext)
        try? projectRepo.register(projectID: document.metadata.id, name: document.metadata.name)

        // Reconcile existing documents against current library
        if !document.schema.categories.isEmpty {
            let service = ReconciliationService(modelContext: modelContext)
            let result = service.reconcile(snapshot: document.schema)
            if result.needsAttention {
                reconciliationResult = result
                showReconciliation = true
            }
        }
    }
}

enum AppTab: Hashable {
    case datasetBuilder
    case referenceLibrary
    case tagLibrary
}
