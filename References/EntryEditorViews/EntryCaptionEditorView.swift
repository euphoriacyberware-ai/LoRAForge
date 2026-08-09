import SwiftUI

// Two columns: a single large preview on the left, caption editing stacked
// above tag selection on the right.

// MARK: - Root

struct EntryCaptionEditorView: View {
    @State private var document = PromptDocument()

    var body: some View {
        #if os(macOS)
        HSplitView {
            EntryPreviewColumn(document: document)
                .frame(minWidth: 320, idealWidth: 480)
            EntryCaptionColumn(document: document)
                .frame(minWidth: 300, idealWidth: 360)
        }
        .frame(minWidth: 760, minHeight: 520)
        #else
        HStack(spacing: 0) {
            EntryPreviewColumn(document: document)
            Divider()
            EntryCaptionColumn(document: document)
        }
        #endif
    }
}

// MARK: - Column 1 · Preview

struct EntryPreviewColumn: View {
    @Bindable var document: PromptDocument

    private var activeSlot: ImageSlot? {
        document.images.first { $0.id == document.selectedImageID } ?? document.images.first
    }

    var body: some View {
        EntryImagePreview(slot: activeSlot)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Column 2 · Caption and tags

struct EntryCaptionColumn: View {
    @Bindable var document: PromptDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            captionSection
            Divider()
            EntryTagPalette(document: document)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SectionLabel(text: "Caption")

                Spacer(minLength: 8)

                Picker("Caption format", selection: $document.captionMode) {
                    ForEach(CaptionMode.allCases) { mode in
                        Image(systemName: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 88)

                Button {
                    document.generateCaption()
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(.borderless)
                .help("Write a caption from the current tags")
                .accessibilityLabel("Generate caption")
            }

            Group {
                switch document.captionMode {
                case .text:
                    SpellCheckingTextEditor(text: $document.caption)
                case .tags:
                    TokenField(tokens: $document.captionTags)
                }
            }
            .frame(minHeight: 160, maxHeight: .infinity)
            .fieldContainer()
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Entry Caption Editor") {
    EntryCaptionEditorView()
}
