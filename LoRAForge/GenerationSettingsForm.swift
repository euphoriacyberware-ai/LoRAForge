import SwiftUI
import DTConfigEditorKit
import DTConfigBridge

/// A form over the common Draw Things settings, editing the same `ConfigEditorModel` as the
/// JSON editor beside it.
///
/// Reads from `model.configuration` and writes one key at a time with `model.set(_:to:)`,
/// so keys the form doesn't show, unknown keys and the document's layout are left alone.
/// Hosts persist through their existing `.onChange(of: model.text)`.
///
/// With `applyKeys`, as in the bulk generation settings sheet, each setting gets an Apply
/// checkbox for its configuration keys; editing a setting ticks it.
struct GenerationSettingsForm: View {
    let model: ConfigEditorModel
    var applyKeys: Binding<Set<String>>? = nil

    @Environment(GenerationService.self) private var generation

    var body: some View {
        if let config = model.configuration {
            form(config)
        } else {
            ContentUnavailableView(
                "Configuration can't be read",
                systemImage: "exclamationmark.triangle",
                description: Text("Fix the configuration on the Configuration JSON tab to edit it here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Below this width the two columns stack into one.
    private static let twoColumnMinWidth: CGFloat = 900

    @State private var availableWidth: CGFloat = 0

    private func form(_ config: DrawThingsConfiguration) -> some View {
        Group {
            if availableWidth >= Self.twoColumnMinWidth {
                HStack(alignment: .top, spacing: 0) {
                    Form { primarySections(config) }
                        .formStyle(.grouped)
                    Form { secondarySections(config) }
                        .formStyle(.grouped)
                }
            } else {
                Form {
                    primarySections(config)
                    secondarySections(config)
                }
                .formStyle(.grouped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    /// Left column: model, size and shift.
    @ViewBuilder
    private func primarySections(_ config: DrawThingsConfiguration) -> some View {
        Section("Model") {
            applying("model") {
                ModelFileField(
                    title: "Model",
                    file: binding(config.model, { .string($0) }, key: "model"),
                    choices: generation.serverModels?.models,
                    unavailableHint: listHint
                )
            }
            applying("sampler") {
                Picker("Sampler", selection: binding(config.sampler, GenerationSettingsWriter.sampler, key: "sampler")) {
                    ForEach(GenerationSettingsWriter.allSamplers, id: \.rawValue) { sampler in
                        Text(GenerationSettingsWriter.samplerName(sampler)).tag(sampler)
                    }
                }
            }
            applying("steps") {
                IntField(
                    title: "Steps",
                    value: binding(Int(config.steps), GenerationSettingsWriter.int, key: "steps"),
                    range: 1...150, step: 1
                )
            }
            applying("guidanceScale") {
                FloatField(
                    title: "CFG",
                    value: binding(config.guidanceScale, GenerationSettingsWriter.float, key: "guidanceScale"),
                    range: 0...30, step: 0.5
                )
            }
        }

        Section {
            SizeControls(width: Int(config.width), height: Int(config.height)) { width, height in
                write("width", GenerationSettingsWriter.int(width))
                write("height", GenerationSettingsWriter.int(height))
            }
            IntField(
                title: "Width",
                value: binding(Int(config.width), GenerationSettingsWriter.int, key: "width"),
                range: 64...4096, step: 64
            )
            IntField(
                title: "Height",
                value: binding(Int(config.height), GenerationSettingsWriter.int, key: "height"),
                range: 64...4096, step: 64
            )
        } header: {
            sectionHeader("Size", keys: "width", "height")
        }

        Section("Shift") {
            applying("resolutionDependentShift") {
                Toggle("Resolution dependent shift", isOn: binding(
                    config.resolutionDependentShift, { .bool($0) }, key: "resolutionDependentShift"
                ))
            }
            applying("shift") {
                FloatField(
                    title: "Shift",
                    value: binding(config.shift, GenerationSettingsWriter.float, key: "shift"),
                    range: 0...10, step: 0.05
                )
                .disabled(config.resolutionDependentShift)
                .help(config.resolutionDependentShift
                      ? "Draw Things calculates shift from the resolution while resolution dependent shift is on."
                      : "")
            }
        }
    }

    /// Right column: LoRAs, refiner and color.
    @ViewBuilder
    private func secondarySections(_ config: DrawThingsConfiguration) -> some View {
        loraSection(config)

        Section("Refiner") {
            applying("refinerModel") {
                ModelFileField(
                    title: "Refiner model",
                    file: Binding(
                        get: { config.refinerModel ?? "" },
                        set: { write("refinerModel", GenerationSettingsWriter.refinerModel($0.isEmpty ? nil : $0)) }
                    ),
                    choices: generation.serverModels?.models,
                    unavailableHint: listHint,
                    placeholder: "None",
                    allowsNone: true
                )
            }
            applying("refinerStart") {
                LabeledContent("Refiner start") {
                    HStack {
                        Slider(
                            value: binding(config.refinerStart, GenerationSettingsWriter.float, key: "refinerStart"),
                            in: 0...1
                        )
                        Text(config.refinerStart, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(config.refinerModel == nil)
                .help("The share of the steps after which the refiner model takes over.")
            }
        }

        Section("Color") {
            applying("colorCalibration") {
                Toggle("Color calibration", isOn: binding(
                    config.colorCalibration == .lab, GenerationSettingsWriter.colorCalibration, key: "colorCalibration"
                ))
            }
        }
    }

    // MARK: - LoRAs

    private func loraSection(_ config: DrawThingsConfiguration) -> some View {
        Section {
            ForEach(Array(config.loras.enumerated()), id: \.offset) { index, lora in
                HStack(alignment: .firstTextBaseline) {
                    ModelFileField(
                        title: "LoRA \(index + 1)",
                        file: Binding(
                            get: { lora.file },
                            set: { newFile in updateLoRAs(config) { $0[index].file = newFile } }
                        ),
                        choices: generation.serverModels?.loras(compatibleWith: config.model),
                        unavailableHint: listHint,
                        warning: generation.serverModels?.isLoRA(lora.file, incompatibleWith: config.model) == true
                            ? "Made for a different model" : nil
                    )
                    FloatField(
                        title: "Weight",
                        value: Binding(
                            get: { lora.weight },
                            set: { newWeight in updateLoRAs(config) { $0[index].weight = newWeight } }
                        ),
                        range: -5...5, step: 0.05,
                        showsTitle: false
                    )
                    .frame(maxWidth: 130)
                    Button(role: .destructive) {
                        updateLoRAs(config) { $0.remove(at: index) }
                    } label: {
                        Label("Remove LoRA", systemImage: "minus.circle")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Remove this LoRA")
                }
            }
            Button {
                updateLoRAs(config) { $0.append(LoRAConfig(file: "", weight: 1.0, mode: .all)) }
            } label: {
                Label("Add LoRA", systemImage: "plus")
            }
        } header: {
            sectionHeader("LoRAs", keys: "loras")
        } footer: {
            if config.loras.contains(where: { $0.mode != .all }) {
                Text("Some LoRAs apply only to the base or refiner model. Change that on the Configuration JSON tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func updateLoRAs(_ config: DrawThingsConfiguration, _ change: (inout [LoRAConfig]) -> Void) {
        var loras = config.loras
        change(&loras)
        write("loras", GenerationSettingsWriter.loras(loras))
    }

    // MARK: - Helpers

    /// Writes one key, ticking its Apply checkbox when the form has them.
    private func write(_ key: String, _ value: JSONValue) {
        model.set(key, to: value)
        applyKeys?.wrappedValue.insert(key)
    }

    private func applyBinding(_ keys: [String]) -> Binding<Bool>? {
        guard let applyKeys else { return nil }
        return Binding(
            get: { keys.allSatisfy(applyKeys.wrappedValue.contains) },
            set: { on in
                if on { applyKeys.wrappedValue.formUnion(keys) } else { applyKeys.wrappedValue.subtract(keys) }
            }
        )
    }

    /// The row with a leading Apply checkbox for `keys`, or the row alone outside bulk editing.
    @ViewBuilder
    private func applying(_ keys: String..., @ViewBuilder content: () -> some View) -> some View {
        if let isOn = applyBinding(keys) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ApplyCheckbox(isOn: isOn)
                content()
            }
        } else {
            content()
        }
    }

    /// A section title with an Apply checkbox covering the whole section when bulk editing.
    @ViewBuilder
    private func sectionHeader(_ title: String, keys: String...) -> some View {
        if let isOn = applyBinding(keys) {
            HStack(spacing: 8) {
                ApplyCheckbox(isOn: isOn)
                Text(title)
            }
        } else {
            Text(title)
        }
    }

    /// A binding that shows the configuration's value and writes changes to one key.
    private func binding<Value: Equatable>(
        _ value: Value, _ encode: @escaping (Value) -> JSONValue, key: String
    ) -> Binding<Value> {
        Binding(
            get: { value },
            set: { newValue in
                guard newValue != value else { return }
                write(key, encode(newValue))
            }
        )
    }

    private var listHint: String {
        switch generation.serverCatalog {
        case .browsingDisabled:
            "Turn on Enable Model Browsing in Draw Things' API server settings to choose from the installed files."
        case .sharedSecretMissing:
            "The server requires a shared secret, so its file list is unavailable."
        case .unavailable, .available:
            "Connect to Draw Things to choose from the installed files."
        }
    }
}

// MARK: - Fields

/// The bulk editor's per-setting checkbox.
private struct ApplyCheckbox: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Apply to every entry", isOn: $isOn)
            .labelsHidden()
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
            .help("Apply this setting to every entry")
    }
}

/// A filename field with a menu of the server's files. Typed names are always accepted, so a
/// file the server doesn't list is kept.
private struct ModelFileField: View {
    let title: String
    @Binding var file: String
    let choices: [ServerModelFile]?
    let unavailableHint: String
    var placeholder = "Filename"
    var allowsNone = false
    /// Shown in place of the usual note, e.g. a LoRA made for a different model family.
    var warning: String? = nil

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    TextField(title, text: $file, prompt: Text(placeholder))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Menu {
                        if allowsNone {
                            Button("None") { file = "" }
                            Divider()
                        }
                        ForEach(choices ?? []) { choice in
                            Button(choice.name) { file = choice.file }
                        }
                    } label: {
                        Label("Choose", systemImage: "chevron.up.chevron.down")
                    }
                    .labelStyle(.iconOnly)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled((choices ?? []).isEmpty)
                    .help(choices == nil ? unavailableHint : "Choose from the server's installed files")
                }
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// The display name of a listed file, or a note that a typed file isn't listed.
    private var note: String? {
        guard let choices, !file.isEmpty else { return nil }
        if let match = choices.first(where: { $0.file == file }) {
            return match.name == file ? nil : match.name
        }
        return "Not in the server's list"
    }
}

private struct IntField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: .number.grouping(.never))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

private struct FloatField: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    var showsTitle = true

    var body: some View {
        if showsTitle {
            LabeledContent(title) { field }
        } else {
            field
        }
    }

    private var field: some View {
        HStack(spacing: 4) {
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...3)))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Stepper(title, value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}

// MARK: - Size

/// Aspect ratio buttons, an orientation switch and megapixel presets over width and height.
private struct SizeControls: View {
    let width: Int
    let height: Int
    let apply: (_ width: Int, _ height: Int) -> Void

    /// The orientation a square size reads as. Square sizes have no orientation of their own,
    /// but the switch still decides how the ratio buttons are drawn and which way the next
    /// ratio picked from 1:1 faces. Follows the size whenever it isn't square.
    @State private var squareIsLandscape = true

    private var isSquare: Bool { width == height }
    private var landscape: Bool {
        isSquare ? squareIsLandscape : ImageSize.isLandscape(width: width, height: height)
    }
    private var matchedRatio: AspectRatio? { ImageSize.matchingRatio(width: width, height: height) }
    private var megapixels: Double { ImageSize.megapixels(width: width, height: height) }

    var body: some View {
        LabeledContent("Aspect ratio") {
            HStack(spacing: 6) {
                ForEach(AspectRatio.common) { ratio in
                    RatioButton(ratio: ratio, landscape: landscape, isSelected: ratio == matchedRatio) {
                        // Keep the current pixel count and orientation.
                        let size = ImageSize.dimensions(ratio: ratio, landscape: landscape, megapixels: megapixels)
                        apply(size.width, size.height)
                    }
                }
                if matchedRatio == nil {
                    Text("Custom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 28)
                Button {
                    squareIsLandscape = !landscape
                    if !isSquare { apply(height, width) }
                } label: {
                    Label(
                        landscape ? "Switch to portrait" : "Switch to landscape",
                        systemImage: landscape ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate"
                    )
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(landscape ? "Switch to portrait" : "Switch to landscape")
            }
        }
        .onChange(of: [width, height], initial: true) {
            if !isSquare { squareIsLandscape = width > height }
        }

        LabeledContent("Megapixels") {
            HStack(spacing: 8) {
                Picker("Megapixels", selection: Binding(
                    get: { ImageSize.matchingPreset(width: width, height: height) },
                    set: { preset in
                        guard let preset else { return }
                        applyMegapixels(preset)
                    }
                )) {
                    ForEach(ImageSize.megapixelPresets, id: \.self) { preset in
                        Text(preset.formatted()).tag(Optional(preset))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text("\(width) × \(height) · \(megapixels.formatted(.number.precision(.fractionLength(2)))) MP")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Keeps the matched ratio, or the exact current proportion when custom, and orientation.
    private func applyMegapixels(_ preset: Double) {
        let size: (width: Int, height: Int)
        if let matchedRatio {
            size = ImageSize.dimensions(ratio: matchedRatio, landscape: landscape, megapixels: preset)
        } else {
            let proportion = Double(max(width, height)) / Double(max(min(width, height), 1))
            size = ImageSize.dimensions(ratio: proportion, landscape: landscape, pixels: preset * ImageSize.megapixel)
        }
        apply(size.width, size.height)
    }
}

/// A ratio drawn as a small rectangle in its proportions, with its label underneath.
private struct RatioButton: View {
    let ratio: AspectRatio
    let landscape: Bool
    let isSelected: Bool
    let action: () -> Void

    private let box: CGFloat = 26

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                let long = box
                let short = box * CGFloat(ratio.short) / CGFloat(ratio.long)
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary, lineWidth: 1.5)
                    .frame(width: landscape ? long : short, height: landscape ? short : long)
                    .frame(width: box, height: box)
                Text(ratio.label(landscape: landscape))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(ratio.label(landscape: landscape)) aspect ratio")
        .accessibilityLabel("\(ratio.label(landscape: landscape)) aspect ratio")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
