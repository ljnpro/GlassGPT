import ChatDomain
import NativeChatBackendCore
import SwiftUI
import UIKit

struct BackendAgentSelectorOverlay: View {
    @Bindable var viewModel: BackendAgentController
    let selectedTheme: AppTheme
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let idiom = UIDevice.current.userInterfaceIdiom
            let horizontalInset = idiom == .pad ? 32.0 : 16.0
            let maxPanelWidth = idiom == .pad ? 680.0 : min(geometry.size.width - (horizontalInset * 2), 560.0)
            let topInset = idiom == .pad ? 76.0 : 60.0

            ZStack(alignment: .top) {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

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
                .frame(maxWidth: maxPanelWidth)
                .padding(.top, topInset)
                .padding(.horizontal, horizontalInset)
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}
