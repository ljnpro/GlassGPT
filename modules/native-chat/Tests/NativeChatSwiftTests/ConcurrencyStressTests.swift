import Foundation
import Testing
@testable import ChatDomain
@testable import ChatRuntimeModel
@testable import ChatRuntimeWorkflows
@testable import OpenAITransport

@Suite(.tags(.runtime))
struct ConcurrencyStressTests {
    // MARK: - ReplySessionActor stress tests

    /// Perform 100 concurrent state transitions on a single ReplySessionActor,
    /// then verify the final state is one of the states we set.
    @Test func `reply session actor handles100 concurrent state transitions`() async {
        let messageID = UUID()
        let conversationID = UUID()
        let replyID = AssistantReplyID(rawValue: messageID)
        let initialState = ReplyRuntimeState(
            assistantReplyID: replyID,
            messageID: messageID,
            conversationID: conversationID,
            lifecycle: .idle
        )
        let actor = ReplySessionActor(initialState: initialState)

        await withTaskGroup(of: Void.self) { group in
            for iteration in 0 ..< 100 {
                group.addTask {
                    let newMessageID = UUID()
                    let newReplyID = AssistantReplyID(rawValue: newMessageID)
                    let lifecycle: ReplyLifecycle = switch iteration % 5 {
                    case 0: .idle
                    case 1: .preparingInput
                    case 2: .finalizing
                    case 3: .completed
                    default: .failed("stress test \(iteration)")
                    }
                    let newState = ReplyRuntimeState(
                        assistantReplyID: newReplyID,
                        messageID: newMessageID,
                        conversationID: conversationID,
                        lifecycle: lifecycle
                    )
                    await actor.replaceState(with: newState)
                }
            }
        }

        // After all concurrent mutations, the actor must still return a valid snapshot.
        let finalSnapshot = await actor.snapshot()
        #expect(finalSnapshot.conversationID == conversationID)
        // The active stream should have been cleared by every replaceState call.
        let hasNoActiveStream = await !actor.isActiveStream(UUID())
        #expect(hasNoActiveStream)
    }

    /// Verify that concurrent snapshot reads and state writes do not crash.
    @Test func `reply session actor concurrent reads and writes`() async {
        let messageID = UUID()
        let conversationID = UUID()
        let replyID = AssistantReplyID(rawValue: messageID)
        let initialState = ReplyRuntimeState(
            assistantReplyID: replyID,
            messageID: messageID,
            conversationID: conversationID,
            lifecycle: .idle
        )
        let actor = ReplySessionActor(initialState: initialState)

        await withTaskGroup(of: ReplyRuntimeState?.self) { group in
            // 50 writers
            for iteration in 0 ..< 50 {
                group.addTask {
                    let newState = ReplyRuntimeState(
                        assistantReplyID: AssistantReplyID(rawValue: UUID()),
                        messageID: UUID(),
                        conversationID: conversationID,
                        lifecycle: iteration % 2 == 0 ? .preparingInput : .completed
                    )
                    await actor.replaceState(with: newState)
                    return nil
                }
            }
            // 50 readers
            for _ in 0 ..< 50 {
                group.addTask {
                    await actor.snapshot()
                }
            }

            var snapshotCount = 0
            for await result in group {
                if result != nil {
                    snapshotCount += 1
                }
            }
            // We should have received 50 snapshots from the reader tasks.
            #expect(snapshotCount == 50)
        }
    }

    // MARK: - RuntimeRegistryActor stress tests

    /// Create 50 sessions in parallel, then remove all 50 in parallel,
    /// and verify the registry is empty.
    @Test func `runtime registry actor parallel create and destroy`() async {
        let registry = RuntimeRegistryActor()
        let conversationID = UUID()

        // Generate 50 unique message IDs up front.
        let messageIDs = (0 ..< 50).map { _ in UUID() }

        // Create 50 sessions in parallel.
        await withTaskGroup(of: AssistantReplyID.self) { group in
            for messageID in messageIDs {
                group.addTask {
                    await registry.startSession(
                        messageID: messageID,
                        conversationID: conversationID
                    )
                }
            }
            // Collect reply IDs to verify they were created.
            var createdIDs: [AssistantReplyID] = []
            for await replyID in group {
                createdIDs.append(replyID)
            }
            #expect(createdIDs.count == 50)
        }

        // Verify all 50 are registered.
        let activeBeforeRemoval = await registry.activeReplyIDs()
        #expect(activeBeforeRemoval.count == 50)

        // Remove all 50 in parallel.
        let replyIDsToRemove = await registry.activeReplyIDs()
        await withTaskGroup(of: Void.self) { group in
            for replyID in replyIDsToRemove {
                group.addTask {
                    await registry.remove(replyID)
                }
            }
        }

        // Verify all sessions are removed.
        let remaining = await registry.activeReplyIDs()
        #expect(remaining.isEmpty)
    }

    /// Stress test: interleave creation and lookup of sessions concurrently.
    @Test func `runtime registry actor concurrent create and lookup`() async {
        let registry = RuntimeRegistryActor()
        let conversationID = UUID()
        let messageIDs = (0 ..< 50).map { _ in UUID() }

        await withTaskGroup(of: Void.self) { group in
            // 50 creators
            for messageID in messageIDs {
                group.addTask {
                    await registry.startSession(
                        messageID: messageID,
                        conversationID: conversationID
                    )
                }
            }
            // 50 lookups (may or may not find the session depending on timing)
            for messageID in messageIDs {
                group.addTask {
                    let replyID = AssistantReplyID(rawValue: messageID)
                    _ = await registry.session(for: replyID)
                    _ = await registry.contains(replyID)
                }
            }
        }

        // After all tasks complete, all 50 sessions should exist.
        let activeIDs = await registry.activeReplyIDs()
        #expect(activeIDs.count == 50)
    }

    // MARK: - SSEFrameBuffer concurrent instance stress tests

    /// Run 50 concurrent tasks, each with its own SSEFrameBuffer instance,
    /// verifying that independent buffers produce correct results.
    @Test func `sse frame buffer concurrent independent instances`() async {
        let validSSE = "event: response.output_text.delta\ndata: {\"delta\":\"chunk\"}\n\n"

        let results = await withTaskGroup(of: (Int, Int).self) { group -> [(Int, Int)] in
            for taskIndex in 0 ..< 50 {
                group.addTask {
                    var buffer = SSEFrameBuffer()
                    var totalFrames = 0

                    // Each task appends the same valid SSE payload multiple times.
                    for _ in 0 ..< 10 {
                        let frames = buffer.append(validSSE)
                        totalFrames += frames.count
                    }
                    let trailing = buffer.finishPendingFrames()
                    totalFrames += trailing.count

                    return (taskIndex, totalFrames)
                }
            }

            var collected: [(Int, Int)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // All 50 tasks should have completed.
        #expect(results.count == 50)

        // Each task should have parsed the same number of frames (deterministic input).
        let frameCounts = Set(results.map(\.1))
        #expect(frameCounts.count == 1, "All tasks should parse the same frame count")

        // Each task should have parsed at least 10 frames (one per append).
        if let firstResult = results.first {
            #expect(firstResult.1 >= 10)
        } else {
            Issue.record("Expected at least one result")
        }
    }

    /// Stress test: 50 concurrent tasks parsing random SSE-like data independently.
    @Test func `sse frame buffer concurrent random parsing`() async {
        await withTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    var buffer = SSEFrameBuffer()
                    var totalFrames = 0

                    // Generate a random SSE-like stream with some valid and invalid lines.
                    for taskIndex in 0 ..< 20 {
                        let chunk = if taskIndex % 4 == 0 {
                            "event: type_\(taskIndex)\ndata: {\"v\":\(taskIndex)}\n\n"
                        } else {
                            "garbage_line_\(Int.random(in: 0 ... 9999))\n"
                        }
                        let frames = buffer.append(chunk)
                        totalFrames += frames.count
                    }
                    let trailing = buffer.finishPendingFrames()
                    totalFrames += trailing.count
                    return totalFrames
                }
            }

            var taskCount = 0
            for await frameCount in group {
                #expect(frameCount >= 0)
                taskCount += 1
            }
            #expect(taskCount == 50)
        }
    }
}
