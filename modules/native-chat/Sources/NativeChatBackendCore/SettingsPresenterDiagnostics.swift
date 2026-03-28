import ChatPresentation
import Foundation
import GeneratedFilesCache
import UIKit

struct SettingsPresenterDiagnostics {
    let appVersionString: String
    let platformString: String
    let generatedImageCacheLimitString: String
    let generatedDocumentCacheLimitString: String
}

@MainActor
func makeSettingsPresenterDiagnostics(
    appVersionString: String?,
    platformString: String?
) -> SettingsPresenterDiagnostics {
    SettingsPresenterDiagnostics(
        appVersionString: appVersionString ?? resolvedAppVersionString(),
        platformString: platformString ?? resolvedPlatformString(),
        generatedImageCacheLimitString: SettingsPresenter.byteCountFormatter.string(
            fromByteCount: GeneratedFileCacheManager.generatedImageCacheLimitBytes
        ),
        generatedDocumentCacheLimitString: SettingsPresenter.byteCountFormatter.string(
            fromByteCount: GeneratedFileCacheManager.generatedDocumentCacheLimitBytes
        )
    )
}

@MainActor
private func resolvedAppVersionString() -> String {
    let info = Bundle.main.infoDictionary
    let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let buildNumber = info?["CFBundleVersion"] as? String ?? "?"
    return "\(shortVersion) (\(buildNumber))"
}

@MainActor
private func resolvedPlatformString() -> String {
    let device = UIDevice.current
    let osName = switch device.userInterfaceIdiom {
    case .pad:
        "iPadOS"
    default:
        "iOS"
    }

    let version = device.systemVersion
    let majorVersion = Int(version.components(separatedBy: ".").first ?? "0") ?? 0

    if majorVersion >= 26 {
        return "\(osName) \(version) · Liquid Glass"
    }

    return "\(osName) \(version)"
}
