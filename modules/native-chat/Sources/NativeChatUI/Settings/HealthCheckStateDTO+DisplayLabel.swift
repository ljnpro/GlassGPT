import BackendContracts

extension HealthCheckStateDTO {
    var displayLabel: String {
        switch self {
        case .healthy:
            String(localized: "Healthy")
        case .degraded:
            String(localized: "Degraded")
        case .unavailable:
            String(localized: "Unavailable")
        case .missing:
            String(localized: "Missing")
        case .invalid:
            String(localized: "Invalid")
        case .unauthorized:
            String(localized: "Unauthorized")
        }
    }
}
