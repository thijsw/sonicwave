import Foundation

/// A counting semaphore for structured concurrency: at most `limit` bodies
/// run concurrently; excess callers suspend (FIFO) until a slot frees.
/// Used to keep artwork fetches under the server's rate limit (issue #4).
actor AsyncLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    func run<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await body()
    }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        // Resumed by release(); the slot transfers without decrementing.
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
