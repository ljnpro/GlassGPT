import ChatDomain
import Testing

/// Tests for domain value types and their invariants.
struct DomainModelTests {
    // MARK: - ModelType

    @Test func `model type raw values`() {
        #expect(ModelType.gpt5_4.rawValue == "gpt-5.4")
        #expect(ModelType.gpt5_4_pro.rawValue == "gpt-5.4-pro")
    }

    @Test func `model type display names`() {
        #expect(ModelType.gpt5_4.displayName == "GPT-5.4")
        #expect(ModelType.gpt5_4_pro.displayName == "GPT-5.4 Pro")
    }

    @Test func `model type available efforts for standard`() {
        let efforts = ModelType.gpt5_4.availableEfforts
        #expect(efforts == [.none, .low, .medium, .high, .xhigh])
    }

    @Test func `model type available efforts for pro`() {
        let efforts = ModelType.gpt5_4_pro.availableEfforts
        #expect(efforts == [.medium, .high, .xhigh])
    }

    @Test func `model type default efforts`() {
        #expect(ModelType.gpt5_4.defaultEffort == .high)
        #expect(ModelType.gpt5_4_pro.defaultEffort == .xhigh)
    }

    @Test func `model type case iterable exhaustiveness`() {
        #expect(ModelType.allCases.count == 2)
    }

    @Test func `model type identifiable`() {
        #expect(ModelType.gpt5_4.id == "gpt-5.4")
        #expect(ModelType.gpt5_4_pro.id == "gpt-5.4-pro")
    }

    // MARK: - ReasoningEffort

    @Test func `reasoning effort display names`() {
        #expect(ReasoningEffort.none.displayName == "None")
        #expect(ReasoningEffort.low.displayName == "Low")
        #expect(ReasoningEffort.medium.displayName == "Medium")
        #expect(ReasoningEffort.high.displayName == "High")
        #expect(ReasoningEffort.xhigh.displayName == "XHigh")
    }

    @Test func `reasoning effort API values`() {
        #expect(ReasoningEffort.none.apiValue == "none")
        #expect(ReasoningEffort.low.apiValue == "low")
        #expect(ReasoningEffort.medium.apiValue == "medium")
        #expect(ReasoningEffort.high.apiValue == "high")
        #expect(ReasoningEffort.xhigh.apiValue == "xhigh")
    }

    @Test func `reasoning effort case count`() {
        #expect(ReasoningEffort.allCases.count == 5)
    }

    // MARK: - ServiceTier

    @Test func `service tier raw values`() {
        #expect(ServiceTier.standard.rawValue == "default")
        #expect(ServiceTier.flex.rawValue == "flex")
    }

    @Test func `service tier display names`() {
        #expect(ServiceTier.standard.displayName == "Standard")
        #expect(ServiceTier.flex.displayName == "Flex")
    }

    @Test func `service tier case count`() {
        #expect(ServiceTier.allCases.count == 2)
    }

    // MARK: - MessageRole

    @Test func `message role raw values`() {
        #expect(MessageRole.user.rawValue == "user")
        #expect(MessageRole.assistant.rawValue == "assistant")
        #expect(MessageRole.system.rawValue == "system")
    }

    @Test func `message role case count`() {
        #expect(MessageRole.allCases.count == 3)
    }

    // MARK: - ConversationConfiguration

    @Test func `configuration equality`() {
        let config1 = ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )
        let config2 = ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )
        #expect(config1 == config2)
    }

    @Test func `configuration inequality`() {
        let config1 = ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )
        let config2 = ConversationConfiguration(
            model: .gpt5_4_pro,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )
        #expect(config1 != config2)
    }

    @Test func `pro mode toggle getter`() {
        let config = ConversationConfiguration(
            model: .gpt5_4_pro,
            reasoningEffort: .xhigh,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )
        #expect(config.proModeEnabled == true)

        let standard = ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )
        #expect(standard.proModeEnabled == false)
    }

    @Test func `pro mode toggle setter`() {
        var config = ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )
        config.proModeEnabled = true
        #expect(config.model == .gpt5_4_pro)

        config.proModeEnabled = false
        #expect(config.model == .gpt5_4)
    }

    @Test func `flex mode toggle getter`() {
        let flex = ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .flex
        )
        #expect(flex.flexModeEnabled == true)

        let standard = ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )
        #expect(standard.flexModeEnabled == false)
    }

    @Test func `flex mode toggle setter`() {
        var config = ConversationConfiguration(
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )
        config.flexModeEnabled = true
        #expect(config.serviceTier == .flex)

        config.flexModeEnabled = false
        #expect(config.serviceTier == .standard)
    }
}
