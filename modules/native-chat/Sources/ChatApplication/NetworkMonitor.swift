import Foundation
import Network
import Observation

/// The current network availability state.
public enum NetworkAvailability: Sendable, Equatable {
    /// The device has a working network path.
    case available
    /// The device has no network connectivity.
    case unavailable
    /// The device has a constrained network path (e.g., Low Data Mode).
    case constrained
}

/// Monitors network path changes and exposes the current availability state.
///
/// Uses `NWPathMonitor` to track network status and publishes updates
/// on the main actor for safe UI consumption.
@MainActor
@Observable
public final class NetworkMonitor: Sendable {
    /// The current network availability.
    public private(set) var availability: NetworkAvailability = .available

    /// Whether the device currently has network connectivity.
    public var isOnline: Bool {
        availability == .available || availability == .constrained
    }

    /// The underlying path monitor.
    private let monitor: NWPathMonitor
    /// The dispatch queue for receiving path updates.
    private let queue: DispatchQueue

    /// Creates and starts a new network monitor.
    public init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.glassgpt.network-monitor")

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch path.status {
                case .satisfied:
                    self.availability = path.isConstrained ? .constrained : .available
                case .unsatisfied:
                    self.availability = .unavailable
                case .requiresConnection:
                    self.availability = .unavailable
                @unknown default:
                    self.availability = .unavailable
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
