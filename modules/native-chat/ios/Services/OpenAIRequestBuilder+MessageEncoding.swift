import Foundation

extension OpenAIRequestBuilder {
    static func buildInputMessages(messages: [APIMessage]) -> [ResponsesInputMessageDTO] {
        var input: [ResponsesInputMessageDTO] = []

        for message in messages {
            let role = message.role == .user ? "user" : "assistant"

            var contentArray: [ResponsesInputMessageDTO.Item] = []
            var hasMultiContent = false

            if !message.content.isEmpty {
                contentArray.append(.inputText(message.content))
            }

            if let imageData = message.imageData {
                hasMultiContent = true
                contentArray.append(.inputImage("data:image/jpeg;base64,\(imageData.base64EncodedString())"))
            }

            for attachment in message.fileAttachments {
                if let fileId = attachment.fileId {
                    hasMultiContent = true
                    contentArray.append(.inputFile(fileId))
                }
            }

            if hasMultiContent || contentArray.count > 1 {
                input.append(
                    ResponsesInputMessageDTO(
                        role: role,
                        content: .items(contentArray)
                    )
                )
            } else if !message.content.isEmpty {
                input.append(
                    ResponsesInputMessageDTO(
                        role: role,
                        content: .text(message.content)
                    )
                )
            }
        }

        return input
    }

    static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": return "application/msword"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": return "application/vnd.ms-excel"
        case "csv": return "text/csv"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}
