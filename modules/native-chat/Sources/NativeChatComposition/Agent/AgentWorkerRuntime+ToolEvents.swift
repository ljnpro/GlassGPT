import ChatDomain
import OpenAITransport

extension AgentWorkerRuntime {
    func applyToolEvent(
        _ event: StreamEvent,
        streamState: inout AgentWorkerStreamState
    ) {
        switch event {
        case let .webSearchStarted(id):
            startToolCall(id: id, type: .webSearch, in: &streamState)
        case let .webSearchSearching(id):
            setToolCallStatus(id: id, status: .searching, in: &streamState)
        case let .webSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed, in: &streamState)
        case let .codeInterpreterStarted(id):
            startToolCall(id: id, type: .codeInterpreter, in: &streamState)
        case let .codeInterpreterInterpreting(id):
            setToolCallStatus(id: id, status: .interpreting, in: &streamState)
        case let .codeInterpreterCodeDelta(id, delta):
            appendToolCode(id: id, delta: delta, in: &streamState)
        case let .codeInterpreterCodeDone(id, code):
            setToolCode(id: id, code: code, in: &streamState)
        case let .codeInterpreterCompleted(id):
            setToolCallStatus(id: id, status: .completed, in: &streamState)
        case let .fileSearchStarted(id):
            startToolCall(id: id, type: .fileSearch, in: &streamState)
        case let .fileSearchSearching(id):
            setToolCallStatus(id: id, status: .fileSearching, in: &streamState)
        case let .fileSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed, in: &streamState)
        default:
            break
        }
    }
}

private extension AgentWorkerRuntime {
    func startToolCall(
        id: String,
        type: ToolCallType,
        in streamState: inout AgentWorkerStreamState
    ) {
        guard !streamState.toolCalls.contains(where: { $0.id == id }) else {
            return
        }
        streamState.toolCalls.append(
            ToolCallInfo(id: id, type: type, status: .inProgress)
        )
    }

    func setToolCallStatus(
        id: String,
        status: ToolCallStatus,
        in streamState: inout AgentWorkerStreamState
    ) {
        guard let index = streamState.toolCalls.firstIndex(where: { $0.id == id }) else {
            return
        }
        streamState.toolCalls[index].status = status
    }

    func appendToolCode(
        id: String,
        delta: String,
        in streamState: inout AgentWorkerStreamState
    ) {
        guard let index = streamState.toolCalls.firstIndex(where: { $0.id == id }) else {
            return
        }
        streamState.toolCalls[index].code = (streamState.toolCalls[index].code ?? "") + delta
    }

    func setToolCode(
        id: String,
        code: String,
        in streamState: inout AgentWorkerStreamState
    ) {
        guard let index = streamState.toolCalls.firstIndex(where: { $0.id == id }) else {
            return
        }
        streamState.toolCalls[index].code = code
    }
}
