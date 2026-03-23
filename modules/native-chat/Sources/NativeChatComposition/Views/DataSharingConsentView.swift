import SwiftUI

/// First-launch consent screen explaining that user data is sent to third-party AI services.
/// Blocks all app functionality until the user explicitly accepts.
package struct DataSharingConsentView: View {
    let onAccept: () -> Void

    /// The consent screen content with disclosure items, privacy link, and accept button.
    package var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(String(localized: "Data Sharing Disclosure"))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 16) {
                    disclosureRow(
                        icon: "brain.head.profile",
                        text: Self.openAIDisclosure
                    )

                    disclosureRow(
                        icon: "cloud.fill",
                        text: Self.cloudflareDisclosure
                    )

                    disclosureRow(
                        icon: "lock.shield",
                        text: Self.localStorageDisclosure
                    )
                }
                .padding(.horizontal, 4)

                if let privacyURL = URL(string: "https://ljnpro.github.io/liquid-glass-chat-support/privacy") {
                    Link(destination: privacyURL) {
                        HStack(spacing: 6) {
                            Text(String(localized: "Read our Privacy Policy"))
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                        }
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier("consent.privacyLink")
                }

                Button {
                    onAccept()
                } label: {
                    Text(String(localized: "I Understand & Agree"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("consent.accept")

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 28)
        }
        .background(.background)
        .interactiveDismissDisabled()
    }

    private static let openAIDisclosure = String(localized: "consent.openai.disclosure")
    private static let cloudflareDisclosure = String(localized: "consent.cloudflare.disclosure")
    private static let localStorageDisclosure = String(localized: "consent.localstorage.disclosure")

    private func disclosureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
