import ChatApplication
import ChatDomain
import Foundation
import GeneratedFilesCore

public struct VisibleProjection: Equatable, Sendable {
    public var conversationID: UUID?
    public var text: String
    public var thinking: String
    public var citations: [URLCitation]
    public var generatedFiles: [GeneratedFileLocalResource]

    public init(
        conversationID: UUID? = nil,
        text: String = "",
        thinking: String = "",
        citations: [URLCitation] = [],
        generatedFiles: [GeneratedFileLocalResource] = []
    ) {
        self.conversationID = conversationID
        self.text = text
        self.thinking = thinking
        self.citations = citations
        self.generatedFiles = generatedFiles
    }

    public static let empty = VisibleProjection()
}

@MainActor
public final class ChatPresenter {
    public private(set) var projection: VisibleProjection
    public let bootstrapPolicy: FeatureBootstrapPolicy

    public init(
        projection: VisibleProjection = .empty,
        bootstrapPolicy: FeatureBootstrapPolicy = .testing
    ) {
        self.projection = projection
        self.bootstrapPolicy = bootstrapPolicy
    }

    public func render(_ nextProjection: VisibleProjection) {
        projection = nextProjection
    }
}
