import Foundation

final class RecoveryStreamProgress {
    var finishedFromStream = false
    var encounteredRecoverableFailure = false
    var receivedAnyRecoveryEvent = false
    var resumeTimedOut = false
}

enum RecoveryStreamMonitoring {
    private static let inactivityTimeoutNanoseconds: UInt64 = 2_000_000_000

    @MainActor
    static func scheduleTimeout(
        onTimeout: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: inactivityTimeoutNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            onTimeout()
        }
    }
}
