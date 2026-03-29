import ChatPersistenceCore
import ChatPresentation
import Foundation
import os

#if DEBUG
extension NativeChatCompositionRoot {
    /// Starts a repeating timer that logs available memory every 30 seconds and warns when below 100 MB.
    func startDebugMemoryMonitor() {
        let logger = Loggers.diagnostics
        let memoryWarningThreshold = 100 * 1024 * 1024
        Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    break
                }
                let available = os_proc_available_memory()
                LaunchTimingStore.shared.availableMemoryBytes = UInt64(available)
                if available < memoryWarningThreshold {
                    logger.error("[Memory] Available memory critically low: \(available / 1024 / 1024) MB")
                }
            }
        }
    }
}
#endif
