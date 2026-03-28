import ChatDomain
import ChatUIComponents
import ConversationSurfaceLogic
import SwiftUI

/// Displays a horizontal scrollable list of citation link cards from web search results.
/// Styled to match the Liquid Glass aesthetic of the app.
package struct CitationLinksView: View {
    let citations: [URLCitation]

    /// Scales card spacing with Dynamic Type for accessibility.
    @ScaledMetric(relativeTo: .caption2) private var cardSpacing: CGFloat = 6

    /// Creates a citation strip for the given citation list.
    package init(citations: [URLCitation]) {
        self.citations = citations
    }

    /// De-duplicated citations by URL
    var cardModels: [CitationLinkCardModel] {
        CitationLinkCardModel.makeModels(from: citations)
    }

    /// The horizontal citation-card strip rendered below assistant messages.
    package var body: some View {
        if !cardModels.isEmpty {
            VStack(alignment: .leading, spacing: cardSpacing) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text(String(localized: "Sources"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
                .accessibilityLabel(String(localized: "Web sources"))
                .accessibilityIdentifier("citations.header")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cardModels) { model in
                            CitationCard(model: model)
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
    let model: CitationLinkCardModel

    var body: some View {
        Link(destination: model.destinationURL) {
            HStack(spacing: 8) {
                // Index badge
                Text("\(model.index)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.blue))

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(model.domain)
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
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityIdentifier("citation.card.\(model.index)")
    }
}
