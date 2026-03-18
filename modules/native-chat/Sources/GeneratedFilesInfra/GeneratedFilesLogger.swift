import OSLog

package enum GeneratedFilesLogger {
    private static let logger = Logger(
        subsystem: "GlassGPT.GeneratedFiles",
        category: "files"
    )

    package static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
