import ChatDomain
import Foundation

/// View-ready citation card model that normalizes titles, domains, and accessibility labels.
public struct CitationLinkCardModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let domain: String
    public let destinationURL: URL
    public let accessibilityLabel: String
    public let index: Int

    /// Creates a citation card model from one URL citation and its displayed ordinal index.
    public init(citation: URLCitation, index: Int) {
        id = citation.id
        self.index = index

        let resolvedDomain = Self.domain(for: citation.url)
        domain = resolvedDomain
        title = citation.title.isEmpty ? resolvedDomain : citation.title
        destinationURL = URL(string: citation.url) ?? URL(fileURLWithPath: "/")
        accessibilityLabel = "Source \(index): \(title)"
    }

    public static func makeModels(from citations: [URLCitation]) -> [CitationLinkCardModel] {
        var seenURLs = Set<String>()
        return citations.compactMap { citation in
            guard seenURLs.insert(citation.url).inserted else {
                return nil
            }
            return citation
        }
        .enumerated()
        .map { index, citation in
            CitationLinkCardModel(citation: citation, index: index + 1)
        }
    }

    public static func domain(for rawURL: String) -> String {
        guard let url = URL(string: rawURL),
              let host = url.host else {
            return rawURL
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
