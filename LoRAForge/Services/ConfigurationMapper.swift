import Foundation
import DrawThingsClient

enum ConfigurationMapper {

    struct ParsedConfig {
        var configuration: DrawThingsConfiguration
        var negativePrompt: String
    }

    static func parse(fromJSON jsonString: String) -> ParsedConfig {
        var config = DrawThingsConfiguration()
        var negativePrompt = ""

        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedConfig(configuration: config, negativePrompt: negativePrompt)
        }

        // Extract negative prompt (not part of DrawThingsConfiguration)
        if let np = dict["negativePrompt"] as? String { negativePrompt = np }

        // Size
        if let v = dict["width"] as? Int { config.width = Int32(v) }
        if let v = dict["height"] as? Int { config.height = Int32(v) }

        // Core generation
        if let v = dict["steps"] as? Int { config.steps = Int32(v) }
        if let v = dict["model"] as? String { config.model = v }
        if let v = dict["guidanceScale"] as? Double { config.guidanceScale = Float(v) }
        if let v = dict["seed"] as? Int { config.seed = Int64(v) }
        if let v = dict["clipSkip"] as? Int { config.clipSkip = Int32(v) }
        if let v = dict["shift"] as? Double { config.shift = Float(v) }
        if let v = dict["strength"] as? Double { config.strength = Float(v) }
        if let v = dict["seedMode"] as? Int { config.seedMode = Int32(v) }

        // Sampler (integer enum)
        if let v = dict["sampler"] as? Int, let s = SamplerType(rawValue: Int8(v)) {
            config.sampler = s
        }

        // Batch
        if let v = dict["batchCount"] as? Int { config.batchCount = Int32(v) }
        if let v = dict["batchSize"] as? Int { config.batchSize = Int32(v) }

        // Guidance
        if let v = dict["imageGuidanceScale"] as? Double { config.imageGuidanceScale = Float(v) }
        if let v = dict["clipWeight"] as? Double { config.clipWeight = Float(v) }
        if let v = dict["guidanceEmbed"] as? Double { config.guidanceEmbed = Float(v) }
        if let v = dict["speedUpWithGuidanceEmbed"] as? Bool { config.speedUpWithGuidanceEmbed = v }
        if let v = dict["cfgZeroStar"] as? Bool { config.cfgZeroStar = v }
        if let v = dict["cfgZeroInitSteps"] as? Int { config.cfgZeroInitSteps = Int32(v) }

        // Quality
        if let v = dict["sharpness"] as? Double { config.sharpness = Float(v) }
        if let v = dict["stochasticSamplingGamma"] as? Double { config.stochasticSamplingGamma = Float(v) }
        if let v = dict["aestheticScore"] as? Double { config.aestheticScore = Float(v) }
        if let v = dict["negativeAestheticScore"] as? Double { config.negativeAestheticScore = Float(v) }

        // Mask/Inpaint
        if let v = dict["maskBlur"] as? Double { config.maskBlur = Float(v) }
        if let v = dict["maskBlurOutset"] as? Int { config.maskBlurOutset = Int32(v) }
        if let v = dict["preserveOriginalAfterInpaint"] as? Bool { config.preserveOriginalAfterInpaint = v }
        if let v = dict["enableInpainting"] as? Bool { config.enableInpainting = v }

        // Text encoders
        if let v = dict["t5TextEncoder"] as? Bool { config.t5TextEncoder = v }
        if let v = dict["separateClipL"] as? Bool { config.separateClipL = v }
        if let v = dict["separateOpenClipG"] as? Bool { config.separateOpenClipG = v }
        if let v = dict["separateT5"] as? Bool { config.separateT5 = v }
        if let v = dict["resolutionDependentShift"] as? Bool { config.resolutionDependentShift = v }
        if let v = dict["clipLText"] as? String, !v.isEmpty { config.clipLText = v }
        if let v = dict["openClipGText"] as? String, !v.isEmpty { config.openClipGText = v }
        if let v = dict["t5Text"] as? String, !v.isEmpty { config.t5Text = v }

        // HiRes Fix
        if let v = dict["hiresFix"] as? Bool { config.hiresFix = v }
        if let v = dict["hiresFixWidth"] as? Int { config.hiresFixWidth = Int32(v) }
        if let v = dict["hiresFixHeight"] as? Int { config.hiresFixHeight = Int32(v) }
        if let v = dict["hiresFixStrength"] as? Double { config.hiresFixStrength = Float(v) }

        // Tiled
        if let v = dict["tiledDiffusion"] as? Bool { config.tiledDiffusion = v }
        if let v = dict["diffusionTileWidth"] as? Int { config.diffusionTileWidth = Int32(v) }
        if let v = dict["diffusionTileHeight"] as? Int { config.diffusionTileHeight = Int32(v) }
        if let v = dict["diffusionTileOverlap"] as? Int { config.diffusionTileOverlap = Int32(v) }
        if let v = dict["tiledDecoding"] as? Bool { config.tiledDecoding = v }
        if let v = dict["decodingTileWidth"] as? Int { config.decodingTileWidth = Int32(v) }
        if let v = dict["decodingTileHeight"] as? Int { config.decodingTileHeight = Int32(v) }
        if let v = dict["decodingTileOverlap"] as? Int { config.decodingTileOverlap = Int32(v) }

        // Stage 2
        if let v = dict["stage2Steps"] as? Int { config.stage2Steps = Int32(v) }
        if let v = dict["stage2Guidance"] as? Double { config.stage2Guidance = Float(v) }
        if let v = dict["stage2Shift"] as? Double { config.stage2Shift = Float(v) }

        // TEA Cache
        if let v = dict["teaCache"] as? Bool { config.teaCache = v }
        if let v = dict["teaCacheStart"] as? Int { config.teaCacheStart = Int32(v) }
        if let v = dict["teaCacheEnd"] as? Int { config.teaCacheEnd = Int32(v) }
        if let v = dict["teaCacheThreshold"] as? Double { config.teaCacheThreshold = Float(v) }
        if let v = dict["teaCacheMaxSkipSteps"] as? Int { config.teaCacheMaxSkipSteps = Int32(v) }

        // Crop/Size
        if let v = dict["cropTop"] as? Int { config.cropTop = Int32(v) }
        if let v = dict["cropLeft"] as? Int { config.cropLeft = Int32(v) }
        if let v = dict["originalImageHeight"] as? Int { config.originalImageHeight = Int32(v) }
        if let v = dict["originalImageWidth"] as? Int { config.originalImageWidth = Int32(v) }
        if let v = dict["targetImageHeight"] as? Int { config.targetImageHeight = Int32(v) }
        if let v = dict["targetImageWidth"] as? Int { config.targetImageWidth = Int32(v) }

        // Upscaler
        if let v = dict["upscalerScaleFactor"] as? Int { config.upscalerScaleFactor = Int32(v) }
        if let v = dict["upscaler"] as? String, !v.isEmpty { config.upscaler = v }

        // Refiner
        if let v = dict["refinerModel"] as? String, !v.isEmpty { config.refinerModel = v }
        if let v = dict["refinerStart"] as? Double { config.refinerStart = Float(v) }
        if let v = dict["zeroNegativePrompt"] as? Bool { config.zeroNegativePrompt = v }

        // Face restoration
        if let v = dict["faceRestoration"] as? String, !v.isEmpty { config.faceRestoration = v }

        // Image prior
        if let v = dict["negativePromptForImagePrior"] as? Bool { config.negativePromptForImagePrior = v }
        if let v = dict["imagePriorSteps"] as? Int { config.imagePriorSteps = Int32(v) }

        // Video
        if let v = dict["fps"] as? Int { config.fps = Int32(v) }
        if let v = dict["motionScale"] as? Int { config.motionScale = Int32(v) }
        if let v = dict["guidingFrameNoise"] as? Double { config.guidingFrameNoise = Float(v) }
        if let v = dict["startFrameGuidance"] as? Double { config.startFrameGuidance = Float(v) }
        if let v = dict["numFrames"] as? Int { config.numFrames = Int32(v) }

        // Causal inference
        if let v = dict["causalInferenceEnabled"] as? Bool { config.causalInferenceEnabled = v }
        if let v = dict["causalInference"] as? Int { config.causalInference = Int32(v) }
        if let v = dict["causalInferencePad"] as? Int { config.causalInferencePad = Int32(v) }

        // LoRAs
        if let loraArray = dict["loras"] as? [[String: Any]] {
            config.loras = loraArray.compactMap { loraDict in
                guard let file = loraDict["file"] as? String else { return nil }
                let weight = (loraDict["weight"] as? Double).map { Float($0) } ?? 1.0
                let modeRaw = (loraDict["mode"] as? Int).map { Int8($0) } ?? 0
                let mode = LoRAMode(rawValue: modeRaw) ?? .all
                return LoRAConfig(file: file, weight: weight, mode: mode)
            }
        }

        // Controls
        if let controlArray = dict["controls"] as? [[String: Any]] {
            config.controls = controlArray.compactMap { ctrlDict in
                guard let file = ctrlDict["file"] as? String else { return nil }
                let weight = (ctrlDict["weight"] as? Double).map { Float($0) } ?? 1.0
                let guidanceStart = (ctrlDict["guidanceStart"] as? Double).map { Float($0) } ?? 0.0
                let guidanceEnd = (ctrlDict["guidanceEnd"] as? Double).map { Float($0) } ?? 1.0
                let modeRaw = (ctrlDict["controlMode"] as? Int).map { Int8($0) } ?? 0
                let controlMode = ControlMode(rawValue: modeRaw) ?? .balanced
                return ControlConfig(
                    file: file,
                    weight: weight,
                    guidanceStart: guidanceStart,
                    guidanceEnd: guidanceEnd,
                    controlMode: controlMode
                )
            }
        }

        // Configuration name
        if let v = dict["name"] as? String, !v.isEmpty { config.name = v }

        return ParsedConfig(configuration: config, negativePrompt: negativePrompt)
    }
}
