import Foundation

@MainActor
public final class BackendDeviceIdentityStore {
    private enum Keys {
        static let deviceID = "backendDeviceID"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var deviceID: String {
        if let existing = defaults.string(forKey: Keys.deviceID), !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: Keys.deviceID)
        return generated
    }
}
