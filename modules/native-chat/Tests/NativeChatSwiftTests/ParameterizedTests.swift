import Foundation
import Testing
@testable import ChatDomain
@testable import OpenAITransport

@Suite(.tags(.parsing))
struct ParameterizedTests {
    // MARK: - Model Display Names

    @Test(arguments: ModelType.allCases)
    func `model has display name`(model: ModelType) {
        #expect(!model.displayName.isEmpty)
        #expect(!model.id.isEmpty)
        #expect(!model.rawValue.isEmpty)
    }

    // MARK: - Reasoning Efforts

    @Test(arguments: ReasoningEffort.allCases)
    func `reasoning effort has display name`(effort: ReasoningEffort) {
        #expect(!effort.displayName.isEmpty)
        #expect(!effort.apiValue.isEmpty)
        #expect(!effort.id.isEmpty)
    }

    // MARK: - Service Tiers

    @Test(arguments: ServiceTier.allCases)
    func `service tier has display name`(tier: ServiceTier) {
        #expect(!tier.displayName.isEmpty)
        #expect(!tier.id.isEmpty)
        #expect(!tier.rawValue.isEmpty)
    }

    // MARK: - Message Roles

    @Test(arguments: MessageRole.allCases)
    func `message role has stable raw value`(role: MessageRole) {
        #expect(!role.rawValue.isEmpty)
        #expect(!role.id.isEmpty)
        let decoded = try? JSONDecoder().decode(
            MessageRole.self,
            from: JSONEncoder().encode(role)
        )
        #expect(decoded == role)
    }

    // MARK: - Error Descriptions

    @Test(arguments: [
        OpenAIServiceError.noAPIKey,
        OpenAIServiceError.invalidURL,
        OpenAIServiceError.httpError(401, "Unauthorized"),
        OpenAIServiceError.httpError(500, "Server Error"),
        OpenAIServiceError.requestFailed("timeout"),
        OpenAIServiceError.cancelled
    ])
    func `error has localized description`(error: OpenAIServiceError) throws {
        let description = try #require(error.errorDescription)
        #expect(!description.isEmpty)
        #expect(!error.localizedDescription.isEmpty)
    }

    // MARK: - Model Available Efforts

    @Test(arguments: ModelType.allCases)
    func `model has valid default effort`(model: ModelType) {
        let efforts = model.availableEfforts
        #expect(!efforts.isEmpty)
        #expect(efforts.contains(model.defaultEffort))
    }
}
