import ChatDomain
import NativeChatBackendCore
import SwiftUI
import UIKit

struct BackendAgentSelectorOverlay: View {
    @Bindable var viewModel: BackendAgentController
    let selectedTheme: AppTheme
    let onDismiss: () -> Void

    var body: some View {
        BackendSelectorOverlayChrome(
            selectedTheme: selectedTheme,
            maxPhonePanelWidth: 560,
            onDismiss: onDismiss
        ) {
            BackendAgentSelectorSheet(
                flexModeEnabled: Binding(
                    get: { viewModel.flexModeEnabled },
                    set: { viewModel.flexModeEnabled = $0 }
                ),
                leaderReasoningEffort: Binding(
                    get: { viewModel.leaderReasoningEffort },
                    set: {
                        viewModel.leaderReasoningEffort = $0
                        viewModel.persistVisibleConfiguration()
                    }
                ),
                workerReasoningEffort: Binding(
                    get: { viewModel.workerReasoningEffort },
                    set: {
                        viewModel.workerReasoningEffort = $0
                        viewModel.persistVisibleConfiguration()
                    }
                ),
                onDone: onDismiss
            )
        }
    }
}
