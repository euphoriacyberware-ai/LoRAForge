import Foundation
import SwiftData

@Model
final class SDConnectionProfile {
    var id: UUID
    var name: String
    var address: String
    var useTLS: Bool
    var sharedSecret: String

    init(name: String, address: String, useTLS: Bool, sharedSecret: String) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.useTLS = useTLS
        self.sharedSecret = sharedSecret
    }
}

@Observable
final class ConnectionProfileRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allProfiles() throws -> [SDConnectionProfile] {
        let descriptor = FetchDescriptor<SDConnectionProfile>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func addProfile(name: String, address: String, useTLS: Bool, sharedSecret: String) throws -> SDConnectionProfile {
        let profile = SDConnectionProfile(
            name: name, address: address, useTLS: useTLS, sharedSecret: sharedSecret
        )
        modelContext.insert(profile)
        try modelContext.save()
        return profile
    }

    func updateProfile(_ profile: SDConnectionProfile) throws {
        try modelContext.save()
    }

    func deleteProfile(_ profile: SDConnectionProfile) throws {
        modelContext.delete(profile)
        try modelContext.save()
    }
}
