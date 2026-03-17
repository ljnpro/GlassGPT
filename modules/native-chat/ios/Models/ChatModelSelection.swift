import Foundation

enum ModelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case gpt5_4 = "gpt-5.4"
    case gpt5_4_pro = "gpt-5.4-pro"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt5_4: return "GPT-5.4"
        case .gpt5_4_pro: return "GPT-5.4 Pro"
        }
    }

    var availableEfforts: [ReasoningEffort] {
        switch self {
        case .gpt5_4:
            return [.none, .low, .medium, .high, .xhigh]
        case .gpt5_4_pro:
            return [.medium, .high, .xhigh]
        }
    }

    var defaultEffort: ReasoningEffort {
        switch self {
        case .gpt5_4: return .high
        case .gpt5_4_pro: return .xhigh
        }
    }
}

enum ReasoningEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "XHigh"
        }
    }

    var apiValue: String {
        rawValue
    }
}

enum ServiceTier: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard = "default"
    case flex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .flex: return "Flex"
        }
    }
}

enum MessageRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case user
    case assistant
    case system

    var id: String { rawValue }
}
