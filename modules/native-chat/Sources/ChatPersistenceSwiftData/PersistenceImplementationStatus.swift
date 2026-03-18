import Foundation

public struct SwiftDataPersistenceModuleReadiness: Equatable, Sendable {
    public let usesLegacyAdapters: Bool

    public init(usesLegacyAdapters: Bool = true) {
        self.usesLegacyAdapters = usesLegacyAdapters
    }
}
