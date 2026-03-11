import SwiftUI
import AppKit

struct PromptDetailView: View {
    @ObservedObject var document: LoRAForgeDocument
    let promptID: UUID
    @State private var showingSlotPicker = false
    @State private var editingSlotIndex: Int?

    private var promptIndex: Int? {
        document.project.prompts.firstIndex(where: { $0.id == promptID })
    }

    var body: some View {
        if let index = promptIndex {
            let prompt = document.project.prompts[index]
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    promptTextEditor(index: index)
                    sourceSlots(prompt: prompt, index: index)
                    generateCountSection(index: index)
                    configOverrideSection(prompt: prompt, index: index)
                    generatedImagesPlaceholder(prompt: prompt)
                }
                .padding()
            }
        } else {
            Text("Prompt not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Prompt Text

    private func promptTextEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prompt Text")
                .font(.headline)
            TextEditor(text: $document.project.prompts[index].text)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 150)
                .border(Color.secondary.opacity(0.3))
                .onChange(of: document.project.prompts[index].text) {
                    document.updateChangeCount(.changeDone)
                }
        }
    }

    // MARK: - Source Image Slots

    private func sourceSlots(prompt: Prompt, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source Images")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(prompt.sourceImageIDs.enumerated()), id: \.offset) { slotIndex, imageID in
                        sourceSlotCell(imageID: imageID, slotIndex: slotIndex, promptIndex: index)
                    }

                    // Add slot button
                    Button {
                        editingSlotIndex = prompt.sourceImageIDs.count
                        showingSlotPicker = true
                    } label: {
                        VStack {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 64, height: 64)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingSlotPicker) {
            SourceImagePickerSheet(
                document: document,
                isPresented: $showingSlotPicker
            ) { selectedID in
                guard let idx = promptIndex else { return }
                if let slotIndex = editingSlotIndex,
                   slotIndex < document.project.prompts[idx].sourceImageIDs.count {
                    document.project.prompts[idx].sourceImageIDs[slotIndex] = selectedID
                } else {
                    document.project.prompts[idx].sourceImageIDs.append(selectedID)
                }
                document.updateChangeCount(.changeDone)
            }
        }
    }

    private func sourceSlotCell(imageID: UUID, slotIndex: Int, promptIndex: Int) -> some View {
        let source = document.project.sourceImages.first(where: { $0.id == imageID })
        return VStack(spacing: 2) {
            if let source,
               let url = document.sourceImageURL(for: source),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                VStack {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 64)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text(source?.label ?? "Missing")
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 64)
        }
        .contextMenu {
            Button("Change…") {
                editingSlotIndex = slotIndex
                showingSlotPicker = true
            }
            Button("Remove Slot") {
                document.project.prompts[promptIndex].sourceImageIDs.remove(at: slotIndex)
                document.updateChangeCount(.changeDone)
            }
        }
    }

    // MARK: - Generate Count

    private func generateCountSection(index: Int) -> some View {
        HStack {
            Text("Generate Count")
                .font(.headline)
            Spacer()
            Stepper(
                value: $document.project.prompts[index].generateCount,
                in: 1...100
            ) {
                Text("\(document.project.prompts[index].generateCount)")
                    .monospacedDigit()
            }
            .onChange(of: document.project.prompts[index].generateCount) {
                document.updateChangeCount(.changeDone)
            }
        }
    }

    // MARK: - Config Override

    private func configOverrideSection(prompt: Prompt, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let hasOverride = prompt.configurationOverrideJSON != nil
            Toggle("Configuration Override", isOn: Binding(
                get: { hasOverride },
                set: { enabled in
                    if enabled {
                        document.project.prompts[index].configurationOverrideJSON = document.project.baseConfigurationJSON
                    } else {
                        document.project.prompts[index].configurationOverrideJSON = nil
                    }
                    document.updateChangeCount(.changeDone)
                }
            ))
            .font(.headline)

            if hasOverride {
                // Phase 9: Full JSON editor
                Text("Configuration override JSON editor — coming in Phase 9")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Generated Images Placeholder

    private func generatedImagesPlaceholder(prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Generated Images")
                .font(.headline)

            if prompt.generatedImages.isEmpty {
                Text("No generated images yet. Use Run to generate.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Phase 11: Image grid
                Text("\(prompt.generatedImages.count) image(s) — grid coming in Phase 11")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Source Image Picker Sheet

struct SourceImagePickerSheet: View {
    @ObservedObject var document: LoRAForgeDocument
    @Binding var isPresented: Bool
    var onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Select Source Image")
                .font(.headline)
                .padding()

            Divider()

            if document.project.sourceImages.isEmpty {
                Text("No source images imported yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                        ForEach(document.project.sourceImages) { source in
                            Button {
                                onSelect(source.id)
                                isPresented = false
                            } label: {
                                VStack(spacing: 4) {
                                    if let url = document.sourceImageURL(for: source),
                                       let nsImage = NSImage(contentsOf: url) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Image(systemName: "photo")
                                            .frame(width: 72, height: 72)
                                            .background(Color.secondary.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    Text(source.label ?? source.filename)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .frame(width: 72)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 350, height: 300)
    }
}
