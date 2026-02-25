import Foundation
import HangulSearch

public enum HangulSearchAsyncAdapter {
    public static func stream<Item>(
        queries: AsyncStream<String>,
        index: HangulSearchIndex<Item>,
        mode: MatchMode = .contains
    ) -> AsyncThrowingStream<[Item], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for await query in queries {
                        try Task.checkCancellation()
                        let results = try await index.search(query, mode: mode)
                        continuation.yield(results)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
