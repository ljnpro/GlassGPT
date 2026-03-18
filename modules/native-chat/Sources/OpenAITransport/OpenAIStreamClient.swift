import Foundation

@MainActor
public protocol OpenAIStreamClient: AnyObject {
    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent>
    func cancel()
}
