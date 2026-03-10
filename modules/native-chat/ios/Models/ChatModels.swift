import SwiftUI
import SwiftData

// MARK: - Model Type

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

    /// Available reasoning effort levels for this model
    var availableEfforts: [ReasoningEffort] {
        switch self {
        case .gpt5_4:
            return [.none, .low, .medium, .high, .xhigh]
        case .gpt5_4_pro:
            return [.medium, .high, .xhigh]
        }
    }

    /// Default reasoning effort for this model
    var defaultEffort: ReasoningEffort {
        switch self {
        case .gpt5_4: return .medium
        case .gpt5_4_pro: return .high
        }
    }
}

// MARK: - Reasoning Effort

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

    /// The value sent to the API (xhigh maps to the API string)
    var apiValue: String {
        rawValue
    }
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Message Role

enum MessageRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case user
    case assistant
    case system

    var id: String { rawValue }
}
