import ChatDomain
import ChatUIComponents
import SwiftUI

/// Displays a horizontal scrollable list of citation link cards from web search results.
/// Styled to match the Liquid Glass aesthetic of the app.
package struct CitationLinksView: View {
    let citations: [URLCitation]

    package init(citations: [URLCitation]) {
        self.citations = citations
    }

    /// De-duplicated citations by URL
    private var uniqueCitations: [URLCitation] {
        var seen = Set<String>()
        return citations.filter { citation in
            if seen.contains(citation.url) { return false }
            seen.insert(citation.url)
            return true
        }
    }

    package var body: some View {
        if !uniqueCitations.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text("Sources")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(uniqueCitations.enumerated()), id: \.element.id) { index, citation in
                            CitationCard(citation: citation, index: index + 1)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.top, 4)
        }
    }
}

/// A single citation card with favicon, title, and domain.
private struct CitationCard: View {
    let citation: URLCitation
    let index: Int

    private var domain: String {
        guard let url = URL(string: citation.url),
              let host = url.host else { return citation.url }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var faviconURL: URL? {
        guard let url = URL(string: citation.url),
              let scheme = url.scheme,
              let host = url.host else { return nil }
        return URL(string: "\(scheme)://\(host)/favicon.ico")
    }

    var body: some View {
        Link(destination: URL(string: citation.url) ?? URL(string: "https://google.com")!) {
            HStack(spacing: 8) {
                // Index badge
                Text("\(index)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.blue))

                VStack(alignment: .leading, spacing: 1) {
                    Text(citation.title.isEmpty ? domain : citation.title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(domain)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .singleSurfaceGlass(
                cornerRadius: 10,
                stableFillOpacity: 0.01,
                borderWidth: 0.7,
                darkBorderOpacity: 0.14,
                lightBorderOpacity: 0.08
            )
        }
        .buttonStyle(.plain)
    }
}
