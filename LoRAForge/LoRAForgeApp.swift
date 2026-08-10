import SwiftUI
import SwiftData

@main
struct LoRAForgeApp: App {
    let modelContainer: ModelContainer
    let tagRepository: TagRepository

    init() {
        let schema = Schema([SDCategory.self, SDTag.self])

        func makeContainer() throws -> ModelContainer {
            let config = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [config])
        }

        do {
            let container: ModelContainer
            do {
                container = try makeContainer()
            } catch {
                // Schema mismatch from a prior build — delete the old store and retry
                let storeURL = ModelConfiguration(schema: schema).url
                try? FileManager.default.removeItem(at: storeURL)
                try? FileManager.default.removeItem(
                    at: storeURL.deletingPathExtension().appendingPathExtension("store-wal"))
                try? FileManager.default.removeItem(
                    at: storeURL.deletingPathExtension().appendingPathExtension("store-shm"))
                container = try makeContainer()
            }
            self.modelContainer = container
            self.tagRepository = TagRepository(modelContext: container.mainContext)
            try tagRepository.seedBuiltInCategoriesIfNeeded()
        } catch {
            fatalError("Could not initialize data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(tagRepository)
        }
        .modelContainer(modelContainer)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(tagRepository)
        }
        .modelContainer(modelContainer)
        #endif
    }
}
