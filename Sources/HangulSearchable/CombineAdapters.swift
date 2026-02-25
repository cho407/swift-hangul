import Foundation
import Combine
import HangulSearch

public enum HangulSearchCombineAdapter {
    public static func publisher<P: Publisher, Item>(
        queries: P,
        index: HangulSearchIndex<Item>,
        mode: MatchMode = .contains,
        debounce: RunLoop.SchedulerTimeType.Stride = .milliseconds(250),
        scheduler: RunLoop = .main
    ) -> AnyPublisher<[Item], Never> where P.Output == String, P.Failure == Never {
        queries
            .debounce(for: debounce, scheduler: scheduler)
            .removeDuplicates()
            .map { query in index.search(query, mode: mode) }
            .eraseToAnyPublisher()
    }
}
