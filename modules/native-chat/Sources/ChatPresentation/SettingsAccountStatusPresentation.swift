import BackendContracts
import Foundation

extension SettingsAccountStore {
    public var syncStatusState: HealthCheckStateDTO? {
        guard isSignedIn else {
            return .missing
        }
        if let connectionStatus, connectionStatus.appCompatibility == .updateRequired {
            return .invalid
        }
        guard let connectionStatus else {
            if lastErrorMessage != nil {
                return .unavailable
            }
            return nil
        }
        if connectionStatus.backend == .healthy,
           connectionStatus.auth == .healthy,
           connectionStatus.sse == .healthy {
            return .healthy
        }
        if connectionStatus.auth == .unauthorized {
            return .unauthorized
        }
        if connectionStatus.sse == .degraded || connectionStatus.backend == .degraded {
            return .degraded
        }
        if connectionStatus.backend == .unavailable || connectionStatus.sse == .unavailable {
            return .unavailable
        }
        return connectionStatus.auth
    }

    public var syncStatusText: String {
        guard isSignedIn else {
            return String(localized: "Not Available")
        }
        if let connectionStatus, connectionStatus.appCompatibility == .updateRequired {
            return String(localized: "App Update Required")
        }
        guard let connectionStatus else {
            if lastErrorMessage != nil {
                return String(localized: "Connection Check Failed")
            }
            return String(localized: "Ready to Verify")
        }
        if connectionStatus.backend == .healthy,
           connectionStatus.auth == .healthy,
           connectionStatus.sse == .healthy {
            return String(localized: "Realtime Sync Ready")
        }
        if connectionStatus.auth == .unavailable,
           connectionStatus.errorSummary == Self.authRuntimeConfigurationErrorSummary {
            return String(localized: "Backend Sign-In Unavailable")
        }
        if connectionStatus.auth == .unauthorized {
            return String(localized: "Session Needs Refresh")
        }
        if connectionStatus.sse == .degraded || connectionStatus.backend == .degraded {
            return String(localized: "Available with Degraded Realtime")
        }
        if connectionStatus.backend == .unavailable || connectionStatus.sse == .unavailable {
            return String(localized: "Backend Unavailable")
        }
        return String(localized: "Needs Attention")
    }

    public var syncStatusDetailText: String? {
        guard isSignedIn else {
            return nil
        }
        if let connectionStatus, connectionStatus.appCompatibility == .updateRequired {
            return String(
                localized: "Install GlassGPT \(connectionStatus.minimumSupportedAppVersion) or newer."
            )
        }
        if let connectionStatus,
           connectionStatus.errorSummary == Self.authRuntimeConfigurationErrorSummary {
            return String(
                localized: "Backend authentication is temporarily unavailable. The server is missing required auth configuration."
            )
        }
        return lastCheckedText.map { String(localized: "Last checked \($0)") }
    }

    public var compatibilityMessage: String? {
        guard let connectionStatus, connectionStatus.appCompatibility == .updateRequired else {
            return nil
        }
        let backendVersion = connectionStatus.backendVersion
        let minimumSupportedVersion = connectionStatus.minimumSupportedAppVersion
        return String(
            localized: "Backend \(backendVersion) requires app version \(minimumSupportedVersion) or newer."
        )
    }

    public var lastCheckedText: String? {
        guard let checkedAt = connectionStatus?.checkedAt else {
            return nil
        }
        return Self.relativeDateFormatter.localizedString(for: checkedAt, relativeTo: Date())
    }
}
