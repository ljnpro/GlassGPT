import BackendContracts
import Foundation

/// Persistence boundary for backend sessions, allowing auth state to be stored without coupling BackendAuth to storage details.
public protocol BackendSessionPersisting {
    func loadSession() -> SessionDTO?
    func saveSession(_ session: SessionDTO) throws
    func clear()
}
