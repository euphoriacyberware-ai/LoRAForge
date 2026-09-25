import Foundation
import DrawThingsClient

/// What the Draw Things server reported about its installed models in the echo reply.
///
/// The server only includes the model lists when "Enable Model Browsing" is on in its API
/// settings; otherwise the reply carries no metadata override at all.
enum ServerCatalog: Equatable {
    /// Not connected, or no reply yet.
    case unavailable
    /// The server requires a shared secret that was not sent or did not match.
    case sharedSecretMissing
    /// The reply had no model lists — model browsing is off on the server.
    case browsingDisabled
    case available(models: Int, loras: Int, controlNets: Int)

    init(reply: EchoReply) {
        if reply.sharedSecretMissing {
            self = .sharedSecretMissing
            return
        }
        let override = reply.override
        guard reply.hasOverride,
              !(override.models.isEmpty && override.loras.isEmpty && override.controlNets.isEmpty)
        else {
            self = .browsingDisabled
            return
        }
        self = .available(
            models: Self.count(override.models),
            loras: Self.count(override.loras),
            controlNets: Self.count(override.controlNets)
        )
    }

    /// Each list is a JSON-encoded array of specs. Empty or unparseable data counts as zero.
    private static func count(_ data: Data) -> Int {
        guard !data.isEmpty,
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
        else { return 0 }
        return array.count
    }
}
