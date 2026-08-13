//
//  EntryEditors.swift
//  LoRA Dataset Builder — UI mockup
//
//  The two per-entry editors reachable from the icon column in the row header.
//

import SwiftUI

// MARK: - Generation editor

struct EntryGenerationEditor: View {
    @Binding var name: String
    @Binding var settings: GenerationSettings
    @Environment(\.dismiss) private var dismiss

    private enum PromptTab: String, CaseIterable { case prompt = "Prompt", negative = "Negative" }
    @State private var tab: PromptTab = .prompt

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Entry Generation Editor")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                promptPane
                    .frame(width: 300)
                Divider()
                seedAndReferencePane
                    .frame(width: 300)
                Divider()
                configPane
                    .frame(minWidth: 280)
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Button("Reset to project defaults") {}
                    .buttonStyle(.link)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 940, height: 640)
    }

    private var promptPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Untitled", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("", selection: $tab) {
                ForEach(PromptTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .padding(.top, 4)

            Group {
                switch tab {
                case .prompt:   TextEditor(text: $settings.prompt)
                case .negative: TextEditor(text: $settings.negativePrompt)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.separator)
            }
        }
        .padding(16)
    }

    private var seedAndReferencePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Seed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Use custom", isOn: $settings.usesCustomSeed)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }

            HStack(spacing: 6) {
                TextField("0", value: $settings.seed, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!settings.usesCustomSeed)
                Button {
                    settings.seed = Int.random(in: 0...999_999_999)
                } label: {
                    Image(systemName: "dice")
                }
                .disabled(!settings.usesCustomSeed)
                .help("Randomize seed")
            }

            Text("Reference Images")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(0..<4, id: \.self) { slot in
                    ReferenceImageWell(filled: slot < settings.referenceImageCount, seed: slot + 7)
                }
            }

            Spacer()
        }
        .padding(16)
    }

    private var configPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Generation Configuration")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Use Custom", isOn: $settings.usesCustomConfig)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }

            TextEditor(text: $settings.configJSON)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .disabled(!settings.usesCustomConfig)
                .foregroundStyle(settings.usesCustomConfig ? .primary : .secondary)
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.separator)
                }

            Text(settings.usesCustomConfig
                 ? "Overrides the project configuration for this entry."
                 : "Turn on Use Custom to edit.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

struct ReferenceImageWell: View {
    let filled: Bool
    let seed: Int

    var body: some View {
        ZStack {
            if filled {
                PlaceholderArt(seed: seed, symbol: "photo")
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 122)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator)
        }
    }
}

// MARK: - Caption editor

struct EntryCaptionEditor: View {
    @Binding var entry: DatasetEntry
    @State var focusedImageID: DatasetImage.ID?
    @Environment(\.dismiss) private var dismiss

    private enum Scope: String, CaseIterable {
        case entry = "Entry default"
        case image = "This image"
    }

    private enum CaptionView: String, CaseIterable { case text, tags }

    @State private var scope: Scope = .entry
    @State private var captionView: CaptionView = .tags
    @State private var filter: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Entry Caption Editor")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(entry.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                imagePane
                    .frame(width: 380)
                Divider()
                captionPane
                    .frame(minWidth: 400)
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                if scope == .image, focusedImage?.captionOverride != nil {
                    Button("Revert to entry caption") {
                        if let index = focusedIndex {
                            entry.images[index].captionOverride = nil
                        }
                    }
                    .buttonStyle(.link)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 900, height: 660)
    }

    // MARK: Left

    private var imagePane: some View {
        VStack(spacing: 10) {
            ZStack {
                if let image = focusedImage {
                    PlaceholderArt(seed: image.artSeed, symbol: image.symbol)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 30))
                            .foregroundStyle(.tertiary)
                        Text("Drop an image here or pick one from the entry.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator)
            }

            if !entry.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(entry.images) { image in
                            PlaceholderArt(seed: image.artSeed, symbol: image.symbol)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(
                                            focusedImageID == image.id ? Color.accentColor : .black.opacity(0.12),
                                            lineWidth: focusedImageID == image.id ? 2.5 : 1
                                        )
                                }
                                .onTapGesture { focusedImageID = image.id }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 52)
            }
        }
        .padding(16)
    }

    // MARK: Right

    private var captionPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Caption")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("", selection: $captionView) {
                    Image(systemName: "text.alignleft").tag(CaptionView.text)
                    Image(systemName: "tag").tag(CaptionView.tags)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 76)

                Button {
                } label: {
                    Image(systemName: "wand.and.sparkles")
                }
                .buttonStyle(.borderless)
                .help("Suggest tags from the image")
            }

            Picker("", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(focusedImage == nil)

            if scope == .image, focusedImage?.captionOverride == nil {
                Text("Inheriting the entry caption. Editing a tag here creates an override for this image.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            captionPreview

            Divider().padding(.vertical, 2)

            Text("Tags")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Filter tags", text: $filter)
                .textFieldStyle(.roundedBorder)

            if captionView == .tags {
                tagLibrary
            } else {
                Spacer()
            }
        }
        .padding(16)
    }

    private var captionPreview: some View {
        ScrollView {
            Text(activeCaption.wrappedValue.isEmpty
                 ? "No tags selected yet."
                 : activeCaption.wrappedValue.rendered)
                .font(.system(size: 12))
                .foregroundStyle(activeCaption.wrappedValue.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: 92)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator)
        }
    }

    private var tagLibrary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(activeCaption.wrappedValue.segments) { segment in
                    let options = TagLibrary.tags(for: segment.categoryName)
                        .filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }

                    if !options.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(segment.categoryName)
                                    .font(.system(size: 11, weight: .medium))
                                if let prefix = segment.prefix {
                                    Text(prefix)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Text(segment.isMulti ? "multi" : "single")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }

                            FlowLayout(spacing: 6) {
                                ForEach(options, id: \.self) { tag in
                                    TagChip(
                                        text: tag,
                                        isSelected: segment.values.contains(tag)
                                    ) {
                                        toggle(tag, in: segment)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Plumbing

    private var focusedIndex: Int? {
        guard let focusedImageID else { return nil }
        return entry.images.firstIndex { $0.id == focusedImageID }
    }

    private var focusedImage: DatasetImage? {
        guard let focusedIndex else { return nil }
        return entry.images[focusedIndex]
    }

    private var activeCaption: Binding<CaptionSettings> {
        if scope == .image, let index = focusedIndex {
            return Binding(
                get: { entry.images[index].captionOverride ?? entry.caption },
                set: { entry.images[index].captionOverride = $0 }
            )
        }
        return $entry.caption
    }

    private func toggle(_ tag: String, in segment: CaptionSegment) {
        var caption = activeCaption.wrappedValue
        guard let index = caption.segments.firstIndex(where: { $0.id == segment.id }) else { return }

        if segment.isMulti {
            if let existing = caption.segments[index].values.firstIndex(of: tag) {
                caption.segments[index].values.remove(at: existing)
            } else {
                // Selection order is preserved as-is; new picks append.
                caption.segments[index].values.append(tag)
            }
        } else {
            caption.segments[index].values = caption.segments[index].values == [tag] ? [] : [tag]
        }

        activeCaption.wrappedValue = caption
    }
}

struct TagChip: View {
    let text: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sample vocabulary

enum TagLibrary {
    static let byCategory: [String: [String]] = [
        "Subject": ["m4y4"],
        "Framing": ["close-up", "medium shot", "full shot", "wide shot"],
        "Camera Angle": ["front view", "three-quarter view", "profile", "from above", "low angle"],
        "Pose": ["standing", "sitting", "walking", "leaning", "arms crossed"],
        "Gaze": ["looking at viewer", "looking away", "eyes closed"],
        "Expression": ["smiling", "neutral expression", "laughing", "serious"],
        "Lighting": ["warm overhead lighting", "soft window light", "golden hour", "studio lighting", "backlit"],
        "Hairstyle": ["hair down", "ponytail", "braid", "bun", "hair tucked behind ear"],
        "Clothing": ["yellow sundress", "white hat", "denim jacket", "black jeans", "wool coat", "gold earrings"],
        "Held-Items": ["black purse", "paper coffee cup", "umbrella", "book"],
        "Background-Location": ["hotel lobby background", "plain grey backdrop", "city street at dusk", "park bench"]
    ]

    static func tags(for category: String) -> [String] {
        byCategory[category] ?? []
    }
}

// MARK: - Previews

#Preview("Generation editor") {
    StatefulPreview()
}

private struct StatefulPreview: View {
    @State private var name = "Hotel lobby set"
    @State private var settings = GenerationSettings(
        prompt: "m4y4 standing in a hotel lobby, warm overhead light",
        negativePrompt: "blurry, extra fingers, watermark",
        referenceImageCount: 2
    )

    var body: some View {
        EntryGenerationEditor(name: $name, settings: $settings)
    }
}

#Preview("Caption editor") {
    CaptionPreviewHost()
}

private struct CaptionPreviewHost: View {
    @State private var entry = DatasetStore.sample.entries[0]

    var body: some View {
        EntryCaptionEditor(entry: $entry, focusedImageID: entry.images.first?.id)
    }
}
