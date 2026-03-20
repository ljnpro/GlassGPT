import ChatDomain
import Testing

/// Tests for ``AppError`` user message and retryability properties.
struct AppErrorTests {
    // MARK: - User Message

    @Test func `transport error has user message`() {
        let error = AppError.transport("Invalid API key")
        #expect(error.userMessage == "Invalid API key")
    }

    @Test func `persistence error has user message`() {
        let error = AppError.persistence("Migration failed")
        #expect(error.userMessage == "Migration failed")
    }

    @Test func `file download error has user message`() {
        let error = AppError.fileDownload("File not found")
        #expect(error.userMessage == "File not found")
    }

    @Test func `runtime error has user message`() {
        let error = AppError.runtime("Invalid state")
        #expect(error.userMessage == "Invalid state")
    }

    @Test func `offline error has localized message`() {
        let error = AppError.offline
        #expect(!error.userMessage.isEmpty)
    }

    // MARK: - Retryability

    @Test func `transport error is retryable`() {
        #expect(AppError.transport("timeout").isRetryable == true)
    }

    @Test func `persistence error is not retryable`() {
        #expect(AppError.persistence("corruption").isRetryable == false)
    }

    @Test func `file download error is retryable`() {
        #expect(AppError.fileDownload("network").isRetryable == true)
    }

    @Test func `runtime error is not retryable`() {
        #expect(AppError.runtime("invalid").isRetryable == false)
    }

    @Test func `offline error is retryable`() {
        #expect(AppError.offline.isRetryable == true)
    }

    // MARK: - Recovery Suggestion

    @Test func `transport error has recovery suggestion`() {
        #expect(AppError.transport("error").recoverySuggestion != nil)
    }

    @Test func `runtime error has no recovery suggestion`() {
        #expect(AppError.runtime("error").recoverySuggestion == nil)
    }

    @Test func `offline error has recovery suggestion`() {
        #expect(AppError.offline.recoverySuggestion != nil)
    }
}
