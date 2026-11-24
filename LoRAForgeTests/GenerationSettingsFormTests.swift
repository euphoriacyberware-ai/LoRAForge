import Testing
import Foundation
@testable import LoRAForge
import DTConfigEditorKit
import DTConfigBridge

@MainActor
struct GenerationSettingsFormTests {

    private let base = """
    {
      "customKey": "kept",
      "loras": [{"file": "style.ckpt", "mode": "refiner", "weight": 0.6}],
      "model": "z_image_turbo_1.0_q8p.ckpt",
      "steps": 8
    }
    """

    // MARK: - Writer round trips through ConfigEditorModel

    @Test func writesScalarFields() throws {
        let model = ConfigEditorModel(text: base)
        model.set("width", to: GenerationSettingsWriter.int(832))
        model.set("height", to: GenerationSettingsWriter.int(1216))
        model.set("steps", to: GenerationSettingsWriter.int(30))
        model.set("guidanceScale", to: GenerationSettingsWriter.float(4.5))
        model.set("shift", to: GenerationSettingsWriter.float(1.0))
        model.set("resolutionDependentShift", to: .bool(true))
        model.set("refinerStart", to: GenerationSettingsWriter.float(0.85))
        model.set("sampler", to: GenerationSettingsWriter.sampler(.eulera))
        model.set("colorCalibration", to: GenerationSettingsWriter.colorCalibration(true))
        model.set("model", to: .string("flux_1_dev_q8p.ckpt"))

        let config = try #require(model.configuration)
        #expect(config.width == 832)
        #expect(config.height == 1216)
        #expect(config.steps == 30)
        #expect(config.guidanceScale == 4.5)
        #expect(config.shift == 1.0)
        #expect(config.resolutionDependentShift)
        #expect(config.refinerStart == 0.85)
        #expect(config.sampler == .eulera)
        #expect(config.colorCalibration == .lab)
        #expect(config.model == "flux_1_dev_q8p.ckpt")
    }

    @Test func floatsAreWrittenWithoutSinglePrecisionNoise() {
        #expect(GenerationSettingsWriter.float(0.85) == .float("0.85"))
        #expect(GenerationSettingsWriter.float(1) == .float("1.0"))
        #expect(GenerationSettingsWriter.float(4.5) == .float("4.5"))
    }

    @Test func editsLeaveOtherKeysAlone() {
        let model = ConfigEditorModel(text: base)
        model.set("steps", to: GenerationSettingsWriter.int(20))
        #expect(model.text.contains(#""customKey": "kept""#))
        #expect(model.unknownKeys.contains { $0.0 == "customKey" })
    }

    @Test func loraEditsPreserveMode() throws {
        let model = ConfigEditorModel(text: base)
        var loras = try #require(model.configuration).loras
        loras[0].weight = 0.9
        loras.append(LoRAConfig(file: "detail.ckpt", weight: 1.0, mode: .all))
        model.set("loras", to: GenerationSettingsWriter.loras(loras))

        let result = try #require(model.configuration).loras
        #expect(result.count == 2)
        #expect(result[0].file == "style.ckpt")
        #expect(result[0].mode == .refiner)
        #expect(abs(result[0].weight - 0.9) < 0.0001)
        #expect(result[1].file == "detail.ckpt")
        #expect(result[1].mode == .all)
    }

    @Test func clearingRefinerDecodesToNil() throws {
        let model = ConfigEditorModel(text: base)
        model.set("refinerModel", to: GenerationSettingsWriter.refinerModel("sdxl_refiner.ckpt"))
        #expect(try #require(model.configuration).refinerModel == "sdxl_refiner.ckpt")
        model.set("refinerModel", to: GenerationSettingsWriter.refinerModel(nil))
        #expect(try #require(model.configuration).refinerModel == nil)
    }

    @Test func colorCalibrationOffWritesNone() throws {
        let model = ConfigEditorModel(text: base)
        model.set("colorCalibration", to: GenerationSettingsWriter.colorCalibration(false))
        #expect(try #require(model.configuration).colorCalibration == .disabled)
    }

    @Test func everySamplerHasAName() {
        let samplers = GenerationSettingsWriter.allSamplers
        #expect(samplers.count == 20)
        #expect(Set(samplers.map(GenerationSettingsWriter.samplerName)).count == 20)
    }

    // MARK: - Server model list

    @Test func parsesServerFiles() {
        let models = Data("""
        [{"name": "Z Image Turbo", "file": "z_image_turbo.ckpt"},
         {"file": "unnamed.ckpt"},
         {"name": "Old", "file": "old.ckpt", "deprecated": true},
         {"name": "No file"},
         {"name": "Dup", "file": "z_image_turbo.ckpt"},
         "junk"]
        """.utf8)
        let list = ServerModelList(modelsJSON: models, lorasJSON: Data())
        #expect(list.models == [
            ServerModelFile(name: "unnamed.ckpt", file: "unnamed.ckpt"),
            ServerModelFile(name: "Z Image Turbo", file: "z_image_turbo.ckpt"),
        ])
        #expect(list.loras.isEmpty)
    }

    @Test func malformedServerDataGivesEmptyList() {
        #expect(ServerModelList.files(from: Data("not json".utf8)).isEmpty)
        #expect(ServerModelList.files(from: Data(#"{"file": "x"}"#.utf8)).isEmpty)
        #expect(ServerModelList.files(from: Data()).isEmpty)
    }

    // MARK: - LoRA compatibility

    private var familyList: ServerModelList {
        ServerModelList(
            modelsJSON: Data("""
            [{"name": "Flux", "file": "flux.ckpt", "version": "flux1"},
             {"name": "Z Image", "file": "z.ckpt", "version": "z_image"},
             {"name": "Mystery", "file": "mystery.ckpt"}]
            """.utf8),
            lorasJSON: Data("""
            [{"name": "Flux style", "file": "flux_style.ckpt", "version": "flux1"},
             {"name": "Z detail", "file": "z_detail.ckpt", "version": "zImage"},
             {"name": "Any", "file": "any.ckpt"}]
            """.utf8)
        )
    }

    @Test func lorasFilterByModelFamily() {
        let files = familyList.loras(compatibleWith: "flux.ckpt").map(\.file)
        #expect(Set(files) == ["flux_style.ckpt", "any.ckpt"])
    }

    @Test func familySpellingsAreNormalized() {
        // "zImage" (camelCase) and "z_image" are the same family.
        let files = familyList.loras(compatibleWith: "z.ckpt").map(\.file)
        #expect(Set(files) == ["z_detail.ckpt", "any.ckpt"])
    }

    @Test func unknownModelShowsEveryLoRA() {
        #expect(familyList.loras(compatibleWith: "mystery.ckpt").count == 3)
        #expect(familyList.loras(compatibleWith: "typed_by_hand.ckpt").count == 3)
    }

    @Test func mismatchOnlyWhenBothFamiliesKnown() {
        let list = familyList
        #expect(list.isLoRA("z_detail.ckpt", incompatibleWith: "flux.ckpt"))
        #expect(!list.isLoRA("flux_style.ckpt", incompatibleWith: "flux.ckpt"))
        #expect(!list.isLoRA("any.ckpt", incompatibleWith: "flux.ckpt"))
        #expect(!list.isLoRA("unlisted.ckpt", incompatibleWith: "flux.ckpt"))
        #expect(!list.isLoRA("z_detail.ckpt", incompatibleWith: "mystery.ckpt"))
    }
}
