import BackendContracts
import Foundation
import Observation
import OSLog

@Observable
@MainActor
public final class BackendSessionStore {
    private static let logger = Logger(subsystem: "GlassGPT", category: "recovery")
    private let persistence: (any BackendSessionPersisting)?

    public private(set) var currentSession: SessionDTO?

    public init(
        session: SessionDTO? = nil,
        persistence: (any BackendSessionPersisting)? = nil
    ) {
        self.persistence = persistence
        currentSession = session ?? persistence?.loadSession()
    }

    public var isSignedIn: Bool {
        currentSession != nil
    }

    public var currentUser: UserDTO? {
        currentSession?.user
    }

    public func replace(session: SessionDTO?) {
        currentSession = session
        persistCurrentSession()
    }

    public func loadSession() -> SessionDTO? {
        currentSession
    }

    public func snapshot() -> BackendSessionSnapshot? {
        guard let currentSession else {
            return nil
        }
        return BackendSessionSnapshot(session: currentSession)
    }

    public func clear() {
        currentSession = nil
        persistence?.clear()
    }

    private func persistCurrentSession() {
        guard let persistence else {
            return
        }

        guard let currentSession else {
            persistence.clear()
            return
        }

        do {
            try persistence.saveSession(currentSession)
        } catch {
            Self.logger.error("Backend session persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
