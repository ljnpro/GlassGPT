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
}

// MARK: - Reasoning Effort

enum ReasoningEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
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
