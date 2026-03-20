import ChatDomain
import Testing

/// Tests for ``AppError`` user message and retryability properties.
struct AppErrorTests {

    // MARK: - User Message

    @Test func transportErrorHasUserMessage() {
        let error = AppError.transport("Invalid API key")
        #expect(error.userMessage == "Invalid API key")
    }

    @Test func persistenceErrorHasUserMessage() {
        let error = AppError.persistence("Migration failed")
        #expect(error.userMessage == "Migration failed")
    }

    @Test func fileDownloadErrorHasUserMessage() {
        let error = AppError.fileDownload("File not found")
        #expect(error.userMessage == "File not found")
    }

    @Test func runtimeErrorHasUserMessage() {
        let error = AppError.runtime("Invalid state")
        #expect(error.userMessage == "Invalid state")
    }

    @Test func offlineErrorHasLocalizedMessage() {
        let error = AppError.offline
        #expect(!error.userMessage.isEmpty)
    }

    // MARK: - Retryability

    @Test func transportErrorIsRetryable() {
        #expect(AppError.transport("timeout").isRetryable == true)
    }

    @Test func persistenceErrorIsNotRetryable() {
        #expect(AppError.persistence("corruption").isRetryable == false)
    }

    @Test func fileDownloadErrorIsRetryable() {
        #expect(AppError.fileDownload("network").isRetryable == true)
    }

    @Test func runtimeErrorIsNotRetryable() {
        #expect(AppError.runtime("invalid").isRetryable == false)
    }

    @Test func offlineErrorIsRetryable() {
        #expect(AppError.offline.isRetryable == true)
    }

    // MARK: - Recovery Suggestion

    @Test func transportErrorHasRecoverySuggestion() {
        #expect(AppError.transport("error").recoverySuggestion != nil)
    }

    @Test func runtimeErrorHasNoRecoverySuggestion() {
        #expect(AppError.runtime("error").recoverySuggestion == nil)
    }

    @Test func offlineErrorHasRecoverySuggestion() {
        #expect(AppError.offline.recoverySuggestion != nil)
    }
}
