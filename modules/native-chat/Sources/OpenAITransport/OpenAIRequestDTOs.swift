import Foundation

public struct ResponsesInputMessageDTO: Codable, Equatable, Sendable {
    public let role: String
    public let content: Content

    public init(role: String, content: Content) {
        self.role = role
        self.content = content
    }

    public enum Content: Codable, Equatable, Sendable {
        case text(String)
        case items([Item])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            do {
                let value = try container.decode(String.self)
                self = .text(value)
                return
            } catch DecodingError.typeMismatch {
                self = .items(try container.decode([Item].self))
            } catch {
                throw error
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let value):
                try container.encode(value)
            case .items(let items):
                try container.encode(items)
            }
        }
    }

    public enum Item: Codable, Equatable, Sendable {
        case inputText(String)
        case inputImage(String)
        case inputFile(String)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
            case fileID = "file_id"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "input_text":
                self = .inputText(try container.decode(String.self, forKey: .text))
            case "input_image":
                self = .inputImage(try container.decode(String.self, forKey: .imageURL))
            case "input_file":
                self = .inputFile(try container.decode(String.self, forKey: .fileID))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unsupported input item type"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .inputText(let text):
                try container.encode("input_text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .inputImage(let imageURL):
                try container.encode("input_image", forKey: .type)
                try container.encode(imageURL, forKey: .imageURL)
            case .inputFile(let fileID):
                try container.encode("input_file", forKey: .type)
                try container.encode(fileID, forKey: .fileID)
            }
        }
    }
}

public struct ResponsesToolDTO: Codable, Equatable, Sendable {
    public let type: String
    public let container: Container?
    public let vectorStoreIDs: [String]?

    public init(
        type: String,
        container: Container? = nil,
        vectorStoreIDs: [String]? = nil
    ) {
        self.type = type
        self.container = container
        self.vectorStoreIDs = vectorStoreIDs
    }

    public struct Container: Codable, Equatable, Sendable {
        public let type: String

        public init(type: String) {
            self.type = type
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case container
        case vectorStoreIDs = "vector_store_ids"
    }
}

public struct ResponsesReasoningRequestDTO: Codable, Equatable, Sendable {
    public let effort: String
    public let summary: String

    public init(effort: String, summary: String) {
        self.effort = effort
        self.summary = summary
    }
}

public struct ResponsesStreamRequestDTO: Codable, Equatable, Sendable {
    public let model: String
    public let input: [ResponsesInputMessageDTO]
    public let stream: Bool
    public let store: Bool
    public let serviceTier: String
    public let tools: [ResponsesToolDTO]
    public let background: Bool?
    public let reasoning: ResponsesReasoningRequestDTO?

    public init(
        model: String,
        input: [ResponsesInputMessageDTO],
        stream: Bool,
        store: Bool,
        serviceTier: String,
        tools: [ResponsesToolDTO],
        background: Bool?,
        reasoning: ResponsesReasoningRequestDTO?
    ) {
        self.model = model
        self.input = input
        self.stream = stream
        self.store = store
        self.serviceTier = serviceTier
        self.tools = tools
        self.background = background
        self.reasoning = reasoning
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case stream
        case store
        case serviceTier = "service_tier"
        case tools
        case background
        case reasoning
    }
}

public struct ResponsesTitleRequestDTO: Codable, Equatable, Sendable {
    public let model: String
    public let instructions: String
    public let input: [ResponsesInputMessageDTO]
    public let stream: Bool
    public let maxOutputTokens: Int

    public init(
        model: String,
        instructions: String,
        input: [ResponsesInputMessageDTO],
        stream: Bool,
        maxOutputTokens: Int
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.stream = stream
        self.maxOutputTokens = maxOutputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case stream
        case maxOutputTokens = "max_output_tokens"
    }
}
