import Foundation
import SwiftData

@Model
final class SDOllamaProfile {
    #Unique<SDOllamaProfile>([\.name])

    var name: String
    var endpoint: String
    var model: String
    var instruction: String

    init(name: String, endpoint: String = "http://localhost:11434",
         model: String = "llava", instruction: String = "") {
        self.name = name
        self.endpoint = endpoint
        self.model = model
        self.instruction = instruction
    }
}
