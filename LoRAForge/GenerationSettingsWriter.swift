import Foundation
import DTConfigEditorKit
import DTConfigBridge

/// Converts form values into the JSON values `ConfigEditorModel.set(_:to:)` writes, in the
/// spellings the Draw Things JSON codec reads.
nonisolated enum GenerationSettingsWriter {
    static func int(_ value: Int) -> JSONValue {
        .int(String(value))
    }

    /// Floats are rounded to four decimals so `0.85` is written as `0.85`, not the
    /// single-precision expansion `0.8500000238`.
    static func float(_ value: Float) -> JSONValue {
        let rounded = (Double(value) * 10_000).rounded() / 10_000
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            return .float(String(format: "%.1f", rounded))
        }
        return .float(String(format: "%g", rounded))
    }

    /// Samplers are written as their integer raw value.
    static func sampler(_ sampler: SamplerType) -> JSONValue {
        .int(String(sampler.rawValue))
    }

    static func colorCalibration(_ enabled: Bool) -> JSONValue {
        .string(enabled ? "lab" : "none")
    }

    /// No refiner is written as an empty string, which the codec reads as nil.
    static func refinerModel(_ file: String?) -> JSONValue {
        .string(file ?? "")
    }

    static func loras(_ loras: [LoRAConfig]) -> JSONValue {
        .array(loras.map { lora in
            .object([
                (key: "file", value: .string(lora.file)),
                (key: "mode", value: .string(modeName(lora.mode))),
                (key: "weight", value: float(lora.weight)),
            ])
        })
    }

    static func modeName(_ mode: LoRAMode) -> String {
        switch mode {
        case .base: "base"
        case .refiner: "refiner"
        default: "all"
        }
    }

    /// Display names for the samplers, in Draw Things' own wording.
    static func samplerName(_ sampler: SamplerType) -> String {
        switch sampler {
        case .dpmpp2mkarras: "DPM++ 2M Karras"
        case .eulera: "Euler A"
        case .ddim: "DDIM"
        case .plms: "PLMS"
        case .dpmppsdekarras: "DPM++ SDE Karras"
        case .unipc: "UniPC"
        case .lcm: "LCM"
        case .eulerasubstep: "Euler A Substep"
        case .dpmppsdesubstep: "DPM++ SDE Substep"
        case .tcd: "TCD"
        case .euleratrailing: "Euler A Trailing"
        case .dpmppsdetrailing: "DPM++ SDE Trailing"
        case .dpmpp2mays: "DPM++ 2M AYS"
        case .euleraays: "Euler A AYS"
        case .dpmppsdeays: "DPM++ SDE AYS"
        case .dpmpp2mtrailing: "DPM++ 2M Trailing"
        case .ddimtrailing: "DDIM Trailing"
        case .unipctrailing: "UniPC Trailing"
        case .unipcays: "UniPC AYS"
        case .tcdtrailing: "TCD Trailing"
        }
    }

    /// Every sampler the configuration can hold, in raw-value order.
    static var allSamplers: [SamplerType] {
        (Int8(0)...Int8(19)).compactMap { SamplerType(rawValue: $0) }
    }
}
