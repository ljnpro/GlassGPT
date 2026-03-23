import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

extension OpenAIStreamEventTranslatorTests {
    @Test func `substring extraction handles emoji characters`() {
        let text = "Hello 😀 World"
        // Characters: H(0) e(1) l(2) l(3) o(4) (5) 😀(6) (7) W(8) o(9) r(10) l(11) d(12)
        #expect(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: text, startIndex: 6, endIndex: 7
            ) == "😀"
        )
        #expect(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: text, startIndex: 5, endIndex: 8
            ) == " 😀 "
        )
    }

    @Test func `substring extraction handles CJK characters`() {
        let text = "abc你好世界def"
        // Characters: a(0) b(1) c(2) 你(3) 好(4) 世(5) 界(6) d(7) e(8) f(9)
        #expect(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: text, startIndex: 3, endIndex: 7
            ) == "你好世界"
        )
    }

    @Test func `substring extraction handles combining characters`() {
        // é as e + combining acute accent is one grapheme cluster
        let text = "cafe\u{0301}s"
        // Characters: c(0) a(1) f(2) é(3) s(4)
        #expect(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: text, startIndex: 2, endIndex: 5
            ) == "fe\u{0301}s"
        )
    }

    @Test func `substring extraction returns empty for empty text`() {
        #expect(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: "", startIndex: 0, endIndex: 1
            ) == ""
        )
    }

    @Test func `substring extraction handles start beyond text length`() {
        #expect(
            OpenAIStreamEventTranslator.extractAnnotatedSubstring(
                from: "abc", startIndex: 10, endIndex: 12
            ) == ""
        )
    }
}
