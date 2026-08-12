import SwiftUI
import SwiftData

@main
struct LoRAForgeApp: App {
    let modelContainer: ModelContainer
    let tagRepository: TagRepository
    let ollamaRepository: OllamaRepository
    let presetRepository: GenerationPresetRepository
    let libraryManager: LibraryManager
    let templateManager: TemplateManager
    let generationService: GenerationService

    init() {
        let schema = Schema([SDCategory.self, SDTag.self, SDOllamaProfile.self, SDGenerationPreset.self])

        func makeContainer() throws -> ModelContainer {
            let config = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [config])
        }

        do {
            let container: ModelContainer
            do {
                container = try makeContainer()
            } catch {
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
            self.ollamaRepository = OllamaRepository(modelContext: container.mainContext)
            self.presetRepository = GenerationPresetRepository(modelContext: container.mainContext)
            self.libraryManager = LibraryManager()
            self.templateManager = TemplateManager()
            self.generationService = GenerationService(library: libraryManager)
            #if DEBUG
            GenerationService.enableDebugLogging()
            #endif
        } catch {
            fatalError("Could not initialize data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(tagRepository)
                .environment(ollamaRepository)
                .environment(presetRepository)
                .environment(libraryManager)
                .environment(templateManager)
                .environment(generationService)
        }
        .modelContainer(modelContainer)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(tagRepository)
                .environment(ollamaRepository)
                .environment(presetRepository)
                .environment(libraryManager)
                .environment(templateManager)
                .environment(generationService)
        }
        .modelContainer(modelContainer)
        #endif
    }
}
