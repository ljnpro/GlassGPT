import ChatDomain
import Testing

/// Tests for domain value types and their invariants.
struct DomainModelTests {

    // MARK: - ModelType

    @Test func modelTypeRawValues() {
        #expect(ModelType.gpt5_4.rawValue == "gpt-5.4")
        #expect(ModelType.gpt5_4_pro.rawValue == "gpt-5.4-pro")
    }

    @Test func modelTypeDisplayNames() {
        #expect(ModelType.gpt5_4.displayName == "GPT-5.4")
        #expect(ModelType.gpt5_4_pro.displayName == "GPT-5.4 Pro")
    }

    @Test func modelTypeAvailableEffortsForStandard() {
        let efforts = ModelType.gpt5_4.availableEfforts
        #expect(efforts == [.none, .low, .medium, .high, .xhigh])
    }

    @Test func modelTypeAvailableEffortsForPro() {
        let efforts = ModelType.gpt5_4_pro.availableEfforts
        #expect(efforts == [.medium, .high, .xhigh])
    }

    @Test func modelTypeDefaultEfforts() {
        #expect(ModelType.gpt5_4.defaultEffort == .high)
        #expect(ModelType.gpt5_4_pro.defaultEffort == .xhigh)
    }

    @Test func modelTypeCaseIterableExhaustiveness() {
        #expect(ModelType.allCases.count == 2)
    }

    @Test func modelTypeIdentifiable() {
        #expect(ModelType.gpt5_4.id == "gpt-5.4")
        #expect(ModelType.gpt5_4_pro.id == "gpt-5.4-pro")
    }

    // MARK: - ReasoningEffort

    @Test func reasoningEffortDisplayNames() {
        #expect(ReasoningEffort.none.displayName == "None")
        #expect(ReasoningEffort.low.displayName == "Low")
        #expect(ReasoningEffort.medium.displayName == "Medium")
        #expect(ReasoningEffort.high.displayName == "High")
        #expect(ReasoningEffort.xhigh.displayName == "XHigh")
    }

    @Test func reasoningEffortAPIValues() {
        #expect(ReasoningEffort.none.apiValue == "none")
        #expect(ReasoningEffort.low.apiValue == "low")
        #expect(ReasoningEffort.medium.apiValue == "medium")
        #expect(ReasoningEffort.high.apiValue == "high")
        #expect(ReasoningEffort.xhigh.apiValue == "xhigh")
    }

    @Test func reasoningEffortCaseCount() {
        #expect(ReasoningEffort.allCases.count == 5)
    }

    // MARK: - ServiceTier

    @Test func serviceTierRawValues() {
        #expect(ServiceTier.standard.rawValue == "default")
        #expect(ServiceTier.flex.rawValue == "flex")
    }

    @Test func serviceTierDisplayNames() {
        #expect(ServiceTier.standard.displayName == "Standard")
        #expect(ServiceTier.flex.displayName == "Flex")
    }

    @Test func serviceTierCaseCount() {
        #expect(ServiceTier.allCases.count == 2)
    }

    // MARK: - MessageRole

    @Test func messageRoleRawValues() {
        #expect(MessageRole.user.rawValue == "user")
        #expect(MessageRole.assistant.rawValue == "assistant")
        #expect(MessageRole.system.rawValue == "system")
    }

    @Test func messageRoleCaseCount() {
        #expect(MessageRole.allCases.count == 3)
    }

    // MARK: - ConversationConfiguration

    @Test func configurationEquality() {
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

    @Test func configurationInequality() {
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

    @Test func proModeToggleGetter() {
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

    @Test func proModeToggleSetter() {
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

    @Test func flexModeToggleGetter() {
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

    @Test func flexModeToggleSetter() {
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
