import Foundation

struct GeneratedFilePrefetchRequest: Hashable {
    let fileID: String
    let containerID: String?
}

@MainActor
final class GeneratedFilePrefetchRegistry {
    private struct Entry {
        var task: Task<Void, Never>
        var requests: Set<GeneratedFilePrefetchRequest>
    }

    private var tasks: [UUID: Entry] = [:]

    func replace(messageID: UUID, with task: Task<Void, Never>) {
        cancel(messageID: messageID)
        tasks[messageID] = Entry(task: task, requests: [])
    }

    func setRequests(_ requests: some Sequence<GeneratedFilePrefetchRequest>, for messageID: UUID) {
        guard var entry = tasks[messageID] else { return }
        entry.requests = Set(requests)
        tasks[messageID] = entry
    }

    func finish(messageID: UUID) {
        tasks.removeValue(forKey: messageID)
    }

    @discardableResult
    func cancel(messageID: UUID) -> Set<GeneratedFilePrefetchRequest> {
        guard let entry = tasks.removeValue(forKey: messageID) else {
            return []
        }
        entry.task.cancel()
        return entry.requests
    }

    @discardableResult
    func cancelAll() -> Set<GeneratedFilePrefetchRequest> {
        let requests = tasks.values.reduce(into: Set<GeneratedFilePrefetchRequest>()) { partialResult, entry in
            partialResult.formUnion(entry.requests)
            entry.task.cancel()
        }
        tasks.removeAll()
        return requests
    }

    deinit {
        for entry in tasks.values {
            entry.task.cancel()
        }
    }
}
