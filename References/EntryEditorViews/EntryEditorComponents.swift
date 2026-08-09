import SwiftUI

// Shared by EntryGenerationEditorView and EntryCaptionEditorView. Named
// separately from the originals in GenerationEditorView.swift so both
// versions can live in the project at once.

// MARK: - Tag palette

struct EntryTagPalette: View {
    @Bindable var document: PromptDocument
    @State private var query = ""

    private var matches: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return document.availableTags }
        return document.availableTags.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Tags")
                Spacer()
                if !document.selectedTags.isEmpty {
                    Button("Clear") { document.selectedTags.removeAll() }
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
            }

            TextField("Filter tags", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                FlowLayout(spacing: 6) {
                    ForEach(matches, id: \.self) { tag in
                        TagChip(title: tag, isSelected: document.selectedTags.contains(tag))
                            .onTapGesture { document.toggleTag(tag) }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fieldContainer()
            .frame(maxHeight: .infinity)
            .overlay {
                if matches.isEmpty {
                    Text("No tags match “\(query)”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Large image preview

struct EntryImagePreview: View {
    let slot: ImageSlot?

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.secondary.opacity(0.10))
            .overlay {
                if let image = slot?.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                        Text("Drop an image here or pick one from the entry.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(24)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            }
    }
}
