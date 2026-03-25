import ChatDomain
import GeneratedFilesCore
import SwiftUI
@testable import NativeChatComposition
@testable import NativeChatUI

@MainActor
extension SnapshotViewTests {
    func testHistorySnapshots() throws {
        _ = try makeHistorySnapshotContainer()
        let store = makeHistoryScreenStore()
        assertViewSnapshots(
            named: "history-list",
            file: snapshotViewTestsFilePath
        ) {
            HistoryView(store: store)
        }
    }

    func testSettingsSnapshots() {
        let viewModel = makeSettingsSnapshotViewModel()
        assertViewSnapshots(
            named: "settings",
            file: snapshotViewTestsFilePath
        ) {
            SettingsView(viewModel: viewModel)
        }

        let gatewayViewModel = makeSettingsSnapshotViewModel()
        gatewayViewModel.credentials.apiKey = "sk-gateway"
        gatewayViewModel.defaults.cloudflareEnabled = true
        gatewayViewModel.credentials.cloudflareHealthStatus = .connected
        gatewayViewModel.cache.generatedImageCacheSizeBytes = 12800
        gatewayViewModel.cache.generatedDocumentCacheSizeBytes = 65536
        assertViewSnapshots(
            named: "settings-gateway",
            file: snapshotViewTestsFilePath
        ) {
            SettingsView(viewModel: gatewayViewModel)
        }

        let unavailableGatewayViewModel = makeSettingsSnapshotViewModel()
        unavailableGatewayViewModel.defaults.cloudflareEnabled = true
        unavailableGatewayViewModel.credentials.cloudflareHealthStatus = .gatewayUnavailable
        unavailableGatewayViewModel.cache.generatedImageCacheSizeBytes = 1024
        unavailableGatewayViewModel.cache.generatedDocumentCacheSizeBytes = 0
        assertViewSnapshots(
            named: "settings-gateway-unavailable",
            file: snapshotViewTestsFilePath
        ) {
            SettingsView(viewModel: unavailableGatewayViewModel)
        }

        let customGatewayViewModel = makeSettingsSnapshotViewModel()
        customGatewayViewModel.defaults.cloudflareEnabled = true
        customGatewayViewModel.credentials.setCloudflareConfigurationMode(.custom)
        customGatewayViewModel.credentials.customCloudflareGatewayBaseURL = ""
        customGatewayViewModel.credentials.customCloudflareAIGToken = ""
        customGatewayViewModel.credentials.cloudflareHealthStatus = .unknown
        assertViewSnapshots(
            named: "settings-gateway-custom",
            file: snapshotViewTestsFilePath
        ) {
            SettingsView(viewModel: customGatewayViewModel)
        }
    }

    func testModelSelectorPhoneLightSnapshot() {
        assertModelSelectorSnapshot(variant: .phoneLight)
    }

    func testModelSelectorPhoneDarkSnapshot() {
        assertModelSelectorSnapshot(variant: .phoneDark)
    }

    func testModelSelectorPadLightSnapshot() {
        assertModelSelectorSnapshot(variant: .padLight)
    }

    func testModelSelectorPadDarkSnapshot() {
        assertModelSelectorSnapshot(variant: .padDark)
    }

    func testFilePreviewSnapshots() throws {
        let imageURL = try makeSnapshotImageFile()
        assertViewSnapshots(
            named: "file-preview-image",
            delay: 0.25,
            file: snapshotViewTestsFilePath
        ) {
            FilePreviewSheet(
                previewItem: FilePreviewItem(
                    url: imageURL,
                    kind: .generatedImage,
                    displayName: "Generated Chart",
                    viewerFilename: "chart.png"
                )
            )
        }

        let pdfURL = try makeSnapshotPDFFile()
        assertViewSnapshots(
            named: "file-preview-pdf",
            delay: 0.25,
            file: snapshotViewTestsFilePath
        ) {
            FilePreviewSheet(
                previewItem: FilePreviewItem(
                    url: pdfURL,
                    kind: .generatedPDF,
                    displayName: "Quarterly Report",
                    viewerFilename: "report.pdf"
                )
            )
        }
    }
}

@MainActor
extension SnapshotViewTests {
    func assertModelSelectorSnapshot(variant: SnapshotTestThemeVariant) {
        assertViewSnapshots(
            named: "model-selector",
            variants: [variant],
            file: snapshotViewTestsFilePath,
            testName: "testModelSelectorSnapshots"
        ) {
            SnapshotModelSelectorHost(variant: variant)
        }
    }
}

private struct SnapshotModelSelectorHost: View {
    let variant: SnapshotTestThemeVariant

    @State private var configuration = ConversationConfiguration(
        model: .gpt5_4_pro,
        reasoningEffort: .xhigh,
        backgroundModeEnabled: true,
        serviceTier: .flex
    )

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                backgroundColor
                    .ignoresSafeArea()

                ModelSelectorSheet(
                    proModeEnabled: Binding(
                        get: { configuration.proModeEnabled },
                        set: { configuration.proModeEnabled = $0 }
                    ),
                    backgroundModeEnabled: $configuration.backgroundModeEnabled,
                    flexModeEnabled: Binding(
                        get: { configuration.flexModeEnabled },
                        set: { configuration.flexModeEnabled = $0 }
                    ),
                    reasoningEffort: $configuration.reasoningEffort,
                    onDone: {}
                )
                .padding(.horizontal, 16)
                .padding(.top, topInset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private var topInset: CGFloat {
        variant.imageConfig.safeArea.top + 56
    }

    private var backgroundColor: Color {
        switch variant.appTheme {
        case .dark:
            .black
        default:
            Color(.systemBackground)
        }
    }
}
