import Foundation
import DrawThingsClient
import DrawThingsKit

/// One installed file the Draw Things server reported: a display name and the filename the
/// configuration refers to.
struct ServerModelFile: Equatable, Hashable, Identifiable {
    let name: String
    let file: String
    /// The model family the file belongs to (e.g. `flux1`, `z_image`), when the server says.
    var version: String? = nil
    var id: String { file }
}

/// The model and LoRA files the server reported in its echo reply.
///
/// Only present when "Enable Model Browsing" is on in the server's API settings. The
/// configuration form offers these as choices; filenames can always be typed by hand.
struct ServerModelList: Equatable {
    var models: [ServerModelFile]
    var loras: [ServerModelFile]

    /// Nil when the reply carries no model lists (browsing off, or a shared-secret failure).
    init?(reply: EchoReply) {
        guard !reply.sharedSecretMissing, reply.hasOverride else { return nil }
        self.init(modelsJSON: reply.override.models, lorasJSON: reply.override.loras)
        if models.isEmpty && loras.isEmpty { return nil }
    }

    init(modelsJSON: Data, lorasJSON: Data) {
        models = Self.files(from: modelsJSON)
        loras = Self.files(from: lorasJSON)
    }

    /// Each list is a JSON array of spec objects with at least `file`; `name` falls back
    /// to the filename. Entries without a file, and deprecated models, are skipped.
    static func files(from data: Data) -> [ServerModelFile] {
        guard !data.isEmpty,
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
        else { return [] }
        var seen = Set<String>()
        let files: [ServerModelFile] = array.compactMap { element in
            guard let object = element as? [String: Any],
                  let file = object["file"] as? String, !file.isEmpty,
                  (object["deprecated"] as? Bool) != true,
                  seen.insert(file).inserted
            else { return nil }
            let name = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? file
            let version = (object["version"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return ServerModelFile(name: name, file: file, version: version)
        }
        return files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Compatibility

    /// The family of a listed model, or nil when the model isn't listed or has none.
    func modelVersion(of modelFile: String) -> String? {
        models.first { $0.file == modelFile }?.version
    }

    /// LoRAs made for the model's family. When the model's family is unknown, every LoRA;
    /// LoRAs with no family are always included.
    func loras(compatibleWith modelFile: String) -> [ServerModelFile] {
        guard let modelVersion = modelVersion(of: modelFile) else { return loras }
        return loras.filter { ModelVersionNormalizer.areCompatible($0.version, modelVersion) }
    }

    /// True only when both the LoRA's and the model's families are known and differ.
    func isLoRA(_ loraFile: String, incompatibleWith modelFile: String) -> Bool {
        guard let modelVersion = modelVersion(of: modelFile),
              let loraVersion = loras.first(where: { $0.file == loraFile })?.version
        else { return false }
        return !ModelVersionNormalizer.areCompatible(loraVersion, modelVersion)
    }
}
