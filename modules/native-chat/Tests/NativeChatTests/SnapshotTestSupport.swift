import ChatDomain
import ChatPersistenceCore
import SnapshotTesting
import SwiftUI
import UIKit

enum SnapshotTestThemeVariant: CaseIterable {
    case phoneLight
    case phoneDark
    case padLight
    case padDark

    var appTheme: AppTheme {
        switch self {
        case .phoneLight, .padLight:
            .light
        case .phoneDark, .padDark:
            .dark
        }
    }

    var snapshotSuffix: String {
        switch self {
        case .phoneLight:
            "phone-light"
        case .phoneDark:
            "phone-dark"
        case .padLight:
            "pad-light"
        case .padDark:
            "pad-dark"
        }
    }

    var imageConfig: ViewImageConfig {
        switch self {
        case .phoneLight:
            Self.makePhoneConfig(style: .light)
        case .phoneDark:
            Self.makePhoneConfig(style: .dark)
        case .padLight:
            Self.makePadConfig(style: .light)
        case .padDark:
            Self.makePadConfig(style: .dark)
        }
    }

    private static func makePhoneConfig(style: UIUserInterfaceStyle) -> ViewImageConfig {
        let traits = UITraitCollection(mutations: {
            $0.userInterfaceIdiom = .phone
            $0.horizontalSizeClass = .compact
            $0.verticalSizeClass = .regular
            $0.displayScale = 3
            $0.userInterfaceStyle = style
        })
        return ViewImageConfig(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            size: CGSize(width: 393, height: 852),
            traits: traits
        )
    }

    private static func makePadConfig(style: UIUserInterfaceStyle) -> ViewImageConfig {
        let traits = UITraitCollection(mutations: {
            $0.userInterfaceIdiom = .pad
            $0.horizontalSizeClass = .regular
            $0.verticalSizeClass = .regular
            $0.displayScale = 2
            $0.userInterfaceStyle = style
        })
        return ViewImageConfig(
            safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
            size: CGSize(width: 1024, height: 1366),
            traits: traits
        )
    }
}

@MainActor
func assertViewSnapshots(
    named baseName: String,
    variants: [SnapshotTestThemeVariant] = SnapshotTestThemeVariant.allCases,
    delay: TimeInterval = 0,
    backgroundColor: UIColor = .clear,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    @ViewBuilder makeView: () -> some View
) {
    for variant in variants {
        let previousTheme = UserDefaults.standard.string(forKey: SettingsStore.Keys.appTheme)
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: SettingsStore.Keys.appTheme)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsStore.Keys.appTheme)
            }
        }

        UserDefaults.standard.set(variant.appTheme.rawValue, forKey: SettingsStore.Keys.appTheme)

        let controller = UIHostingController(
            rootView: makeView()
                .environment(\.hapticsEnabled, true)
                .preferredColorScheme(variant.appTheme.colorScheme)
        )
        let canvasSize = variant.imageConfig.size ?? CGSize(width: 1, height: 1)
        controller.loadViewIfNeeded()
        controller.view.backgroundColor = backgroundColor
        controller.preferredContentSize = canvasSize
        controller.view.bounds = CGRect(origin: .zero, size: canvasSize)
        controller.view.frame = CGRect(origin: .zero, size: canvasSize)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        if delay > 0 {
            RunLoop.main.run(until: Date().addingTimeInterval(delay))
        }

        assertSnapshot(
            of: controller,
            as: .image(on: variant.imageConfig),
            named: "\(baseName)-\(variant.snapshotSuffix)",
            file: file,
            testName: testName,
            line: line
        )
    }
}

@MainActor
func cleanupSnapshotHarness(_ harness: SnapshotHarness) {
    try? FileManager.default.removeItem(at: harness.cacheRoot)
}

enum NativeChatSnapshotFileError: Error {
    case saveFailed
}

@MainActor
func makeSnapshotImageFile() throws -> URL {
    let size = CGSize(width: 1200, height: 900)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
        UIColor.systemIndigo.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIColor.white.setFill()
        context.fill(CGRect(x: 80, y: 120, width: 1040, height: 620))
        let title = "Generated Chart" as NSString
        title.draw(
            at: CGPoint(x: 120, y: 180),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.black
            ]
        )
    }

    guard let data = image.pngData() else {
        throw NativeChatSnapshotFileError.saveFailed
    }

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-preview-image.png")
    try data.write(to: url, options: .atomic)
    return url
}

@MainActor
func makeSnapshotPDFFile() throws -> URL {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: bounds)
    let data = renderer.pdfData { context in
        context.beginPage()
        let title = "Quarterly Report" as NSString
        title.draw(
            at: CGPoint(x: 48, y: 52),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.black
            ]
        )
        let body = "The 5.6.0 release candidate completed successfully." as NSString
        body.draw(
            in: CGRect(x: 48, y: 120, width: 516, height: 200),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
        )
    }

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-preview-document.pdf")
    try data.write(to: url, options: .atomic)
    return url
}
