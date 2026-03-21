import Foundation

enum OpenAIResponseOutputSelection {
    static func preferredMessageItems(from response: ResponsesResponseDTO) -> [ResponsesOutputItemDTO] {
        guard let output = response.output else {
            return []
        }

        let messageItems = output.filter { item in
            item.type == "message" && outputText(in: item) != nil
        }

        guard !messageItems.isEmpty else {
            return []
        }

        if let finalAssistant = messageItems.last(where: {
            $0.role == "assistant" && $0.phase == "final_answer"
        }) {
            return [finalAssistant]
        }

        if let completedAssistant = messageItems.last(where: {
            $0.role == "assistant" && $0.status == "completed"
        }) {
            return [completedAssistant]
        }

        if let assistant = messageItems.last(where: { $0.role == "assistant" }) {
            return [assistant]
        }

        if let lastMessage = messageItems.last {
            return [lastMessage]
        }

        return []
    }

    static func outputText(in item: ResponsesOutputItemDTO) -> String? {
        guard let content = item.content else { return nil }
        let text = content
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined()
        return text.isEmpty ? nil : text
    }
}
