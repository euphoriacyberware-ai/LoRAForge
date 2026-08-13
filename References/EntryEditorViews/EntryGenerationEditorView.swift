import SwiftUI

// Same three-column shape as GenerationEditorView, minus the caption block.
// Column 1 is now name + prompt tabs only, so the editor fills the column.

// MARK: - Root

struct EntryGenerationEditorView: View {
    @State private var document = PromptDocument()

    var body: some View {
        #if os(macOS)
        HSplitView {
            EntryPromptColumn(document: document)
                .frame(minWidth: 300, idealWidth: 360)
            EntryAssetsColumn(document: document)
                .frame(minWidth: 280, idealWidth: 320)
            EntryConfigurationColumn(document: document)
                .frame(minWidth: 260, idealWidth: 300)
        }
        .frame(minWidth: 920, minHeight: 620)
        #else
        HStack(spacing: 0) {
            EntryPromptColumn(document: document)
            Divider()
            EntryAssetsColumn(document: document)
            Divider()
            EntryConfigurationColumn(document: document)
        }
        #endif
    }
}

// MARK: - Column 1 · Name and prompts

struct EntryPromptColumn: View {
    @Bindable var document: PromptDocument
    @State private var tab: PromptTab = .prompt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Name")
                TextField("Untitled", text: $document.name)
                    .textFieldStyle(.roundedBorder)
            }

            TabView(selection: $tab) {
                ForEach(PromptTab.allCases) { item in
                    SpellCheckingTextEditor(text: binding(for: item))
                        .padding(4)
                        .tabItem { Text(item.title) }
                        .tag(item)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func binding(for tab: PromptTab) -> Binding<String> {
        switch tab {
        case .prompt: $document.prompt
        case .negative: $document.negativePrompt
        }
    }
}

// MARK: - Column 2 · Seed, reference images, tags

struct EntryAssetsColumn: View {
    @Bindable var document: PromptDocument

    private let grid = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            seedSection
            imageGrid
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var seedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: "Seed")
                Spacer()
                Toggle("Use custom", isOn: $document.useCustomSeed)
                    .font(.callout)
            }

            HStack(spacing: 6) {
                TextField("Random", value: $document.seed, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .disabled(!document.useCustomSeed)

                Button {
                    document.randomizeSeed()
                } label: {
                    Image(systemName: "die.face.5")
                }
                .disabled(!document.useCustomSeed)
                .help("Roll a new seed")
                .accessibilityLabel("Roll a new seed")
            }
        }
    }

    private var imageGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Reference Images")

            LazyVGrid(columns: grid, spacing: 10) {
                ForEach(document.images) { slot in
                    ImageSlotView(slot: slot, isSelected: document.selectedImageID == slot.id)
                        .onTapGesture { document.selectedImageID = slot.id }
                }
            }
        }
    }
}

// MARK: - Column 3 · Generation configuration

struct EntryConfigurationColumn: View {
    @Bindable var document: PromptDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Generation Configuration")
                Spacer(minLength: 8)
                Toggle("Use Custom", isOn: $document.useCustomConfiguration)
                    .font(.callout)
                    .fixedSize()
            }

            SpellCheckingTextEditor(
                text: $document.configuration,
                isSpellCheckingEnabled: false,
                isEditable: document.useCustomConfiguration,
                font: SpellCheckingTextEditor.monospacedFont()
            )
            .fieldContainer(isEnabled: document.useCustomConfiguration)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(document.useCustomConfiguration
                 ? "Overrides the preset for this item."
                 : "Turn on Use Custom to edit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Preview

#Preview("Entry Generation Editor") {
    EntryGenerationEditorView()
}
