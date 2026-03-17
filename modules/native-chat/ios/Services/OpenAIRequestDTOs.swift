import Foundation

struct ResponsesInputMessageDTO: Codable, Equatable, Sendable {
    let role: String
    let content: Content

    init(role: String, content: Content) {
        self.role = role
        self.content = content
    }

    enum Content: Codable, Equatable, Sendable {
        case text(String)
        case items([Item])

        init(from decoder: Decoder) throws {
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

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let value):
                try container.encode(value)
            case .items(let items):
                try container.encode(items)
            }
        }
    }

    enum Item: Codable, Equatable, Sendable {
        case inputText(String)
        case inputImage(String)
        case inputFile(String)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
            case fileID = "file_id"
        }

        init(from decoder: Decoder) throws {
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

        func encode(to encoder: Encoder) throws {
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

struct ResponsesToolDTO: Codable, Equatable, Sendable {
    let type: String
    let container: Container?
    let vectorStoreIDs: [String]?

    init(
        type: String,
        container: Container? = nil,
        vectorStoreIDs: [String]? = nil
    ) {
        self.type = type
        self.container = container
        self.vectorStoreIDs = vectorStoreIDs
    }

    struct Container: Codable, Equatable, Sendable {
        let type: String
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case container
        case vectorStoreIDs = "vector_store_ids"
    }
}

struct ResponsesReasoningRequestDTO: Codable, Equatable, Sendable {
    let effort: String
    let summary: String
}

struct ResponsesStreamRequestDTO: Codable, Equatable, Sendable {
    let model: String
    let input: [ResponsesInputMessageDTO]
    let stream: Bool
    let store: Bool
    let serviceTier: String
    let tools: [ResponsesToolDTO]
    let background: Bool?
    let reasoning: ResponsesReasoningRequestDTO?

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

struct ResponsesTitleRequestDTO: Codable, Equatable, Sendable {
    let model: String
    let instructions: String
    let input: [ResponsesInputMessageDTO]
    let stream: Bool
    let maxOutputTokens: Int

    private enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case stream
        case maxOutputTokens = "max_output_tokens"
    }
}
