public enum ModelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case gpt5_4 = "gpt-5.4"
    case gpt5_4_pro = "gpt-5.4-pro"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gpt5_4: return "GPT-5.4"
        case .gpt5_4_pro: return "GPT-5.4 Pro"
        }
    }

    public var availableEfforts: [ReasoningEffort] {
        switch self {
        case .gpt5_4:
            return [.none, .low, .medium, .high, .xhigh]
        case .gpt5_4_pro:
            return [.medium, .high, .xhigh]
        }
    }

    public var defaultEffort: ReasoningEffort {
        switch self {
        case .gpt5_4: return .high
        case .gpt5_4_pro: return .xhigh
        }
    }
}

public enum ReasoningEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case low
    case medium
    case high
    case xhigh

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "XHigh"
        }
    }

    public var apiValue: String {
        rawValue
    }
}

public enum ServiceTier: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard = "default"
    case flex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .flex: return "Flex"
        }
    }
}

public enum MessageRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case user
    case assistant
    case system

    public var id: String { rawValue }
}
