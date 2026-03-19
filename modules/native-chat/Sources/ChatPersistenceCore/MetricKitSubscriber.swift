import Foundation
import MetricKit
import OSLog

/// Receives MetricKit diagnostic and metric payloads, logging them via the diagnostics logger.
public final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber, Sendable {
    private let logger = Loggers.diagnostics

    /// Processes periodic metric payloads from the system.
    public func didReceive(_ payloads: [MXMetricPayload]) {
        logger.info("[MetricKit] Received \(payloads.count) metric payload(s)")
        for payload in payloads {
            logger.debug("[MetricKit] Metric payload timeStamp: \(payload.timeStampEnd.description)")
        }
    }

    /// Processes diagnostic payloads including crash, hang, and disk-write reports.
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        logger.info("[MetricKit] Received \(payloads.count) diagnostic payload(s)")
        for payload in payloads {
            if let crashDiagnostics = payload.crashDiagnostics, !crashDiagnostics.isEmpty {
                logger.error("[MetricKit] \(crashDiagnostics.count) crash diagnostic(s)")
            }
            if let hangDiagnostics = payload.hangDiagnostics, !hangDiagnostics.isEmpty {
                logger.error("[MetricKit] \(hangDiagnostics.count) hang diagnostic(s)")
            }
            if let diskWriteDiagnostics = payload.diskWriteExceptionDiagnostics, !diskWriteDiagnostics.isEmpty {
                logger.info("[MetricKit] \(diskWriteDiagnostics.count) disk write diagnostic(s)")
            }
        }
    }
}
