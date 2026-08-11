import SwiftUI

struct GenerationEditorView: View {
    @Binding var entry: EntryDocument
    let referenceImages: [ReferenceImageDocument]
    let bundleURL: URL
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingPromptTab = true // true = prompt, false = negative
    @State private var showingRefPicker = false
    @State private var refPickerSlot = 0

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                promptPanel
                    .frame(minWidth: 220, idealWidth: 280)
                Divider()
                seedAndReferencesPanel
                    .frame(minWidth: 200, idealWidth: 240)
                Divider()
                configPanel
                    .frame(minWidth: 240, idealWidth: 300)
            }
            .navigationTitle("Entry generation editor")
            #if os(macOS)
            .frame(minWidth: 700, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Left: Name + Prompt

    private var promptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Name", text: $entry.name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: entry.name) { onChanged() }
            }

            Picker("", selection: $showingPromptTab) {
                Text("Prompt").tag(true)
                Text("Negative").tag(false)
            }
            .pickerStyle(.segmented)

            if showingPromptTab {
                TextEditor(text: $entry.generationPrompt)
                    .font(.body)
                    .onChange(of: entry.generationPrompt) { onChanged() }
            } else {
                TextEditor(text: $entry.generationNegativePrompt)
                    .font(.body)
                    .onChange(of: entry.generationNegativePrompt) { onChanged() }
            }
        }
        .padding()
    }

    // MARK: - Center: Seed + Reference Images

    private var seedAndReferencesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Seed
            HStack {
                Text("Seed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Use custom", isOn: $entry.useCustomSeed)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: entry.useCustomSeed) { onChanged() }
            }

            HStack {
                TextField("0", value: Binding(
                    get: { entry.generationSeed ?? 0 },
                    set: { entry.generationSeed = $0; onChanged() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .disabled(!entry.useCustomSeed)

                Button {
                    entry.generationSeed = Int64(Int.random(in: 0...Int(UInt32.max)))
                    onChanged()
                } label: {
                    Image(systemName: "dice")
                }
                .disabled(!entry.useCustomSeed)
            }

            Divider()

            // Reference Images — four slots
            HStack {
                Text("Reference images")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.referenceImageIDs.count)/4")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(0..<4, id: \.self) { slot in
                    refSlotView(slot: slot)
                }
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingRefPicker) {
            RefPickerSheet(
                referenceImages: referenceImages,
                bundleURL: bundleURL,
                alreadyAssigned: Set(entry.referenceImageIDs),
                onSelect: { refID in
                    if refPickerSlot < entry.referenceImageIDs.count {
                        entry.referenceImageIDs[refPickerSlot] = refID
                    } else {
                        entry.referenceImageIDs.append(refID)
                    }
                    onChanged()
                    showingRefPicker = false
                }
            )
        }
    }

    @ViewBuilder
    private func refSlotView(slot: Int) -> some View {
        let refID = slot < entry.referenceImageIDs.count ? entry.referenceImageIDs[slot] : nil
        let refImage = refID.flatMap { id in referenceImages.first { $0.id == id } }

        ZStack(alignment: .topTrailing) {
            if let refImage {
                let imageURL = bundleURL.appending(path: "references/\(refImage.filename)")
                #if os(macOS)
                if let nsImage = NSImage(contentsOf: imageURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    emptySlot(slot: slot)
                }
                #else
                if let data = try? Data(contentsOf: imageURL),
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    emptySlot(slot: slot)
                }
                #endif

                Button {
                    if slot < entry.referenceImageIDs.count {
                        entry.referenceImageIDs.remove(at: slot)
                        onChanged()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .padding(2)
            } else {
                emptySlot(slot: slot)
            }
        }
    }

    private func emptySlot(slot: Int) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.1))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.quaternary)
            }
            .onTapGesture {
                guard entry.referenceImageIDs.count < 4 || slot < entry.referenceImageIDs.count else { return }
                guard !referenceImages.isEmpty else { return }
                refPickerSlot = slot
                showingRefPicker = true
            }
    }

    // MARK: - Right: Generation Configuration

    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Generation configuration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Use custom", isOn: $entry.useCustomConfig)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: entry.useCustomConfig) { onChanged() }
            }

            if entry.useCustomConfig {
                TextEditor(text: $entry.generationConfigJSON)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: entry.generationConfigJSON) { onChanged() }
            } else {
                TextEditor(text: .constant(defaultConfigPreview))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .disabled(true)
            }

            if !entry.useCustomConfig {
                Text("Turn on Use custom to edit.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("Seed and batch size are overridden by the app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private var defaultConfigPreview: String {
        """
        {
          "steps": 30,
          "cfg_scale": 7.0,
          "sampler": "dpmpp_2m",
          "scheduler": "karras",
          "width": 1024,
          "height": 1024,
          "batch_size": 1
        }
        """
    }
}

// MARK: - Reference Image Picker Sheet

private struct RefPickerSheet: View {
    let referenceImages: [ReferenceImageDocument]
    let bundleURL: URL
    let alreadyAssigned: Set<UUID>
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                    ForEach(referenceImages) { ref in
                        let isAssigned = alreadyAssigned.contains(ref.id)
                        Button { onSelect(ref.id) } label: {
                            refThumbnail(ref)
                                .opacity(isAssigned ? 0.4 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .disabled(isAssigned)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose reference image")
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 300)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func refThumbnail(_ ref: ReferenceImageDocument) -> some View {
        let url = bundleURL.appending(path: "references/\(ref.filename)")
        #if os(macOS)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #else
        if let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #endif
    }
}
