import ChatDomain
import Foundation
import SwiftData

/// Test fixture that provides sample conversation data with rich Markdown content.
public enum RichAssistantReplyFixture {
    /// Sample user prompt text (Chinese).
    public static let userPrompt = "写个1000词抒情文章"
    /// Default conversation title for prose fixtures.
    public static let conversationTitle = "Rich Markdown Sample"
    /// Default conversation title for code-block fixtures.
    public static let codeConversationTitle = "Rich Markdown Code Sample"
    /// Default conversation title for table fixtures.
    public static let tableConversationTitle = "Rich Markdown Table Sample"

    /// Sample assistant reply containing multi-paragraph prose.
    public static let assistantReply = """
    当然。下面是一篇中文抒情短文，题目自拟，风格偏细腻温柔。

    《岁月深处有微光》

    人这一生，总是在与时光相逢，也总是在与时光告别。许多日子看似平常，像被风轻轻翻过的一页纸，等到某个安静的傍晚，才会发现它们其实一直留在心里，从未真正走远。

    记忆是有温度的。它不像石头那样冰冷坚硬，也不像烟雾那样飘散无痕。它更像冬夜里的一盏灯，光不必很盛，却足够照亮心里最柔软的一角，让人在喧嚣里忽然安静下来。

    这些微光，常常藏在极寻常的片刻里。比如午后的一杯热茶，窗台上缓慢移动的日影，旧书页里一片干花，或者深夜回家时，楼上那扇还亮着的窗。它们很轻，却足以支撑人走过漫长的岁月。

    人也许就是靠着这些光，学会与自己和解。后来我们才慢慢明白，真正让人坚定下来的，不是喧腾的胜利，而是在疲惫与沉默里，依然愿意替自己留下一点温柔和希望。
    """

    /// Sample assistant reply containing an embedded Swift code block.
    public static let assistantReplyWithCodeBlock = """
    当然。下面是一段带有代码示例的说明，外层依然应该保持为同一个 assistant 气泡。

    《把思路写成代码》

    有些想法适合用文字慢慢展开，也有些想法适合先用一小段代码把结构立起来。真正重要的不是形式，而是这些片段最后仍然服务于同一个完整回答。

    ```swift
    struct Reminder {
        let title: String
        let notes: [String]
    }

    let reminder = Reminder(
        title: "岁月深处有微光",
        notes: ["保留温柔", "继续前进", "不要拆成多个 bubble"]
    )
    ```

    当代码块结束后，后面的段落也应该继续留在同一个消息里，而不是被切成新的外层卡片。这样用户看到的仍然是一条完整答复。
    """

    /// Sample assistant reply containing a Markdown pipe table.
    public static let assistantReplyWithTable = """
    当然。下面先给出一个简洁对比表，再补一句结论。

    | 方案 | 风险 | 适合场景 |
    | :--- | ---: | :---: |
    | 增量发布 | 低 | 稳定上线 |
    | 原地替换 | 高 | 紧急但可回滚 |
    | 双写迁移 | 中 | 需要长期兼容 |

    如果目标是稳定发布，优先选择增量发布，并保留显式回滚门。
    """

    /// Creates a ``Conversation`` populated with a user message and an assistant reply.
    public static func makeConversation(
        title: String = conversationTitle,
        userPrompt: String = userPrompt,
        assistantReply: String = assistantReply,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) -> Conversation {
        let conversation = Conversation(
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )

        let userMessage = Message(
            role: .user,
            content: userPrompt
        )
        let assistantMessage = Message(
            role: .assistant,
            content: assistantReply
        )

        conversation.messages = [userMessage, assistantMessage]
        userMessage.conversation = conversation
        assistantMessage.conversation = conversation
        return conversation
    }

    /// Inserts the conversation and all its messages into the given model context and saves.
    public static func insertConversation(
        _ conversation: Conversation,
        into modelContext: ModelContext
    ) throws {
        modelContext.insert(conversation)
        for message in conversation.messages {
            modelContext.insert(message)
        }
        try modelContext.save()
    }
}
