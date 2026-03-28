import ChatPresentation
import SwiftUI

struct SettingsAgentDefaultsView: View {
    @Bindable var viewModel: AgentSettingsDefaultsStore

    var body: some View {
        Form {
            SettingsAgentDefaultsSection(viewModel: viewModel)
        }
        .listSectionSpacing(.compact)
        .navigationTitle(String(localized: "Agent Settings"))
    }
}
