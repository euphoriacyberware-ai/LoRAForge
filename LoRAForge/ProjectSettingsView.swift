import SwiftUI
import TaggingCore

struct ProjectSettingsView: View {
    @Binding var document: ProjectDocument
    let onChanged: () -> Void

    @Environment(TagRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String
    @State private var categories: [TagCategory] = []

    init(document: Binding<ProjectDocument>, onChanged: @escaping () -> Void) {
        self._document = document
        self.onChanged = onChanged
        self._projectName = State(initialValue: document.wrappedValue.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $projectName)
                        .onChange(of: projectName) {
                            document.name = projectName
                            onChanged()
                        }
                }

                Section("Category order and enabled state") {
                    Text("These settings are independent of the app defaults.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(orderedCategories) { cat in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { document.categoryEnabled[cat.id] ?? true },
                                set: {
                                    document.categoryEnabled[cat.id] = $0
                                    onChanged()
                                }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(cat.name)
                                    if let prefix = cat.prefix, !prefix.isEmpty {
                                        Text(prefix)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                    .onMove(perform: moveCategories)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Project settings")
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 350)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                categories = (try? repo.allCategories()) ?? []
            }
        }
    }

    private var orderedCategories: [TagCategory] {
        document.categoryOrder.compactMap { catID in
            categories.first { $0.id == catID }
        }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var order = document.categoryOrder
        order.move(fromOffsets: source, toOffset: destination)

        // Subject must stay at position 0
        if let subjectIdx = order.firstIndex(of: BuiltInCategory.subject.id), subjectIdx != 0 {
            return
        }

        document.categoryOrder = order
        onChanged()
    }
}
