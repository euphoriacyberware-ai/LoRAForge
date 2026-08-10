import Foundation
import SwiftData

@Model
final class SDKnownProject {
    #Unique<SDKnownProject>([\.projectID])

    var projectID: UUID
    var name: String
    var lastOpened: Date

    init(projectID: UUID, name: String) {
        self.projectID = projectID
        self.name = name
        self.lastOpened = Date()
    }
}
