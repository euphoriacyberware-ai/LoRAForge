import SwiftUI

/// Project tab for defining macros: named prompt snippets that entry prompts
/// reference as `<Name>` and that expand when a generation request is built.
struct MacrosView: View {
    @Binding var document: ProjectDocument
    let bundleURL: URL
    let onChanged: () -> Void

    @State private var selectedMacroID: UUID?
    @State private var macroToDelete: ProjectMacro?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if document.macros.isEmpty && undefinedReferences.isEmpty {
                ContentUnavailableView(
                    "No macros",
                    systemImage: "text.badge.plus",
                    description: Text("Add a macro, then reference it in an entry prompt as <Name>. It is replaced with the macro's text when the image is generated.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    macroList
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(document.name)
        .alert("Delete macro?", isPresented: .init(
            get: { macroToDelete != nil },
            set: { if !$0 { macroToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { macroToDelete = nil }
        } message: {
            if let macro = macroToDelete {
                let usage = MacroExpander.usageCount(of: macro.name, in: document.entries)
                if usage > 0 {
                    Text("<\(macro.name)> is used in \(usage) entr\(usage == 1 ? "y" : "ies"). Those references will be sent as literal text.")
                } else {
                    Text("<\(macro.name)> is not used in any entries.")
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("\(document.macros.count) macro\(document.macros.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
            Button { addMacro(named: nextUntitledName()) } label: {
                Label("Add macro", systemImage: "plus")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - List

    private var undefinedReferences: [String] {
        MacroExpander.undefinedReferences(in: document.entries, macros: document.macros)
    }

    private var macroList: some View {
        List(selection: $selectedMacroID) {
            if !document.macros.isEmpty {
                Section("Macros") {
                    ForEach(document.macros) { macro in
                        macroRow(macro)
                            .tag(macro.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) { macroToDelete = macro }
                            }
                    }
                }
            }
            let undefined = undefinedReferences
            if !undefined.isEmpty {
                Section {
                    ForEach(undefined, id: \.self) { name in
                        HStack {
                            Label("<\(name)>", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Create") { addMacro(named: name) }
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Undefined references")
                } footer: {
                    Text("Used in entry prompts but not defined here. These are sent as literal text.")
                }
            }
        }
    }

    private func macroRow(_ macro: ProjectMacro) -> some View {
        let usage = MacroExpander.usageCount(of: macro.name, in: document.entries)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(macro.name)
                if macro.text.isEmpty {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .help("This macro has no text")
                }
            }
            Text(usage == 0 ? "Not used" : "Used in \(usage) entr\(usage == 1 ? "y" : "ies")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selectedMacroID, let index = document.macros.firstIndex(where: { $0.id == id }) {
            MacroDetailView(
                macro: Binding(
                    get: { document.macros[index] },
                    set: { document.macros[index] = $0; onChanged() }
                ),
                allMacros: document.macros,
                entries: document.entries,
                onDelete: { macroToDelete = document.macros[index] }
            )
            .id(id)
        } else {
            ContentUnavailableView(
                "No macro selected",
                systemImage: "text.cursor",
                description: Text("Select a macro to edit its name and text.")
            )
        }
    }

    // MARK: - Actions

    private func nextUntitledName() -> String {
        var n = 1
        var name = "New macro"
        while MacroExpander.validateName(name, existing: document.macros) == .duplicate {
            n += 1
            name = "New macro \(n)"
        }
        return name
    }

    private func addMacro(named name: String) {
        let macro = ProjectMacro(name: name)
        document.macros.append(macro)
        selectedMacroID = macro.id
        onChanged()
    }

    private func performDelete() {
        guard let macro = macroToDelete else { return }
        document.macros.removeAll { $0.id == macro.id }
        if selectedMacroID == macro.id { selectedMacroID = nil }
        macroToDelete = nil
        onChanged()
    }
}

/// Name and text editor for one macro. The name is committed only when valid;
/// the text writes through on every edit.
private struct MacroDetailView: View {
    @Binding var macro: ProjectMacro
    let allMacros: [ProjectMacro]
    let entries: [EntryDocument]
    let onDelete: () -> Void

    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    private var nameError: MacroExpander.NameError? {
        MacroExpander.validateName(nameDraft, existing: allMacros, excluding: macro.id)
    }

    private var isRenaming: Bool {
        MacroExpander.key(nameDraft) != MacroExpander.key(macro.name)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $nameDraft)
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }
                if let error = nameError {
                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if isRenaming {
                    let usage = MacroExpander.usageCount(of: macro.name, in: entries)
                    if usage > 0 {
                        Text("<\(macro.name)> is used in \(usage) entr\(usage == 1 ? "y" : "ies"). Renaming does not update those prompts; their references will become undefined.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Name")
            } footer: {
                Text("Reference in prompts as <\(macro.name)>. Matching ignores case.")
            }

            Section("Text") {
                TextEditor(text: $macro.text)
                    .font(.body)
                    .frame(minHeight: 160)
                if macro.text.isEmpty {
                    Text("This macro is empty. References to it expand to nothing.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button("Delete macro", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
        .onAppear { nameDraft = macro.name }
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard nameError == nil else {
            nameDraft = macro.name
            return
        }
        if trimmed != macro.name { macro.name = trimmed }
        nameDraft = trimmed
    }
}
