import SwiftUI

struct SettingsNavigationRowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color(red: 0.04, green: 0.26, blue: 0.68))

            Text(title)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
