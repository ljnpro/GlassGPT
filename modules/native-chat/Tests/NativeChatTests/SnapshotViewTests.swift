import ChatDomain
import ChatPersistenceSwiftData
import GeneratedFilesCore
import SnapshotTesting
import SwiftUI
import XCTest
@testable import NativeChatComposition
@testable import NativeChatUI

let snapshotViewTestsFilePath: StaticString = #filePath

@MainActor
final class SnapshotViewTests: XCTestCase {
    override func invokeTest() {
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" ? .all : .missing

        withSnapshotTesting(record: recordMode) {
            super.invokeTest()
        }
    }

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            UIView.setAnimationsEnabled(false)
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            UIView.setAnimationsEnabled(true)
        }
        super.tearDown()
    }

    func testChatSnapshots() throws {
        try assertChatEmptySnapshot()
        try assertChatStandardSnapshot()
        try assertChatRichMarkdownSnapshot()
        try assertChatCodeBlockSnapshot()
        try assertChatTableSnapshot()
        try assertChatStreamingSnapshot()
        try assertChatErrorSnapshot()
        try assertChatRestoringSnapshot()
        try assertChatRecoveringSnapshot()
    }

    func testPresentationComponentSnapshots() {
        assertThinkingViewSnapshot()
        assertThinkingIndicatorSnapshot()
        assertCodeBlockSnapshot()
        assertCodeInterpreterIndicatorSnapshot()
        assertCodeInterpreterResultSnapshot()
        assertFileAttachmentsRowSnapshot()
        assertCitationLinksSnapshot()
    }
}
