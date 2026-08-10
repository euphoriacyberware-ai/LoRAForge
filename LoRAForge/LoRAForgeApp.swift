import SwiftUI
import SwiftData

@main
struct LoRAForgeApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                SDTagCategory.self,
                SDTag.self,
                SDKnownProject.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        let repo = SwiftDataCategoryRepository(modelContext: modelContainer.mainContext)
        do {
            try repo.seedBuiltInsIfNeeded()
        } catch {
            print("Warning: failed to seed built-in categories: \(error)")
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: { LoRAForgeDocument() }) { config in
            ContentView(document: config.document)
        }
        .modelContainer(modelContainer)

        #if os(macOS)
        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)
        #endif
    }
}
