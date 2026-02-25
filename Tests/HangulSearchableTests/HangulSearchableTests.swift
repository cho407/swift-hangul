import XCTest
import HangulSearch
@testable import HangulSearchable

final class HangulSearchableTests: XCTestCase {
    private struct Item: HangulSearchable, Sendable, Equatable {
        let id: Int
        let name: String

        var hangulSearchKey: String {
            name
        }
    }

    private func wait(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    func testControllerDebounceUsesLatestQuery() async {
        let items: [Item] = [
            .init(id: 1, name: "프론트엔드"),
            .init(id: 2, name: "백엔드"),
            .init(id: 3, name: "데이터"),
        ]

        let index = HangulSearchIndex(items: items)
        let controller = await MainActor.run {
            HangulSearchController(
                index: index,
                options: .init(
                    debounceMilliseconds: 60,
                    minimumQueryLength: 1,
                    fallbackToSimilarityWhenNoMatch: false
                )
            )
        }

        await MainActor.run {
            controller.submit("ㅂ")
            controller.submit("ㅍ")
        }

        await wait(milliseconds: 240)

        let resultIDs = await MainActor.run {
            controller.results.map(\.id)
        }
        XCTAssertEqual(resultIDs, [1])
    }

    func testControllerSimilarityFallbackForLayoutMistype() async {
        let items: [Item] = [
            .init(id: 1, name: "프론트엔드"),
            .init(id: 2, name: "백엔드"),
        ]

        let index = HangulSearchIndex(items: items)
        let controller = await MainActor.run {
            HangulSearchController(
                index: index,
                options: .init(
                    debounceMilliseconds: 0,
                    minimumQueryLength: 1,
                    fallbackToSimilarityWhenNoMatch: true
                )
            )
        }

        await MainActor.run {
            controller.submit("vmfhsxmdpsem", immediate: true)
        }

        await wait(milliseconds: 200)

        let firstID = await MainActor.run {
            controller.results.first?.id
        }
        XCTAssertEqual(firstID, 1)
    }

    func testControllerMinimumLengthAndClearBehavior() async {
        let items: [Item] = [
            .init(id: 1, name: "프론트엔드"),
            .init(id: 2, name: "백엔드"),
        ]

        let index = HangulSearchIndex(items: items)
        let controller = await MainActor.run {
            HangulSearchController(
                index: index,
                options: .init(
                    debounceMilliseconds: 0,
                    minimumQueryLength: 2,
                    clearResultsWhenQueryEmpty: true,
                    fallbackToSimilarityWhenNoMatch: false
                )
            )
        }

        await MainActor.run {
            controller.submit("ㅍ", immediate: true)
        }
        await wait(milliseconds: 80)

        let tooShortCount = await MainActor.run {
            controller.results.count
        }
        XCTAssertEqual(tooShortCount, 0)

        await MainActor.run {
            controller.submit("ㅍㄹ", immediate: true)
        }
        await wait(milliseconds: 160)

        let matchedCount = await MainActor.run {
            controller.results.count
        }
        XCTAssertGreaterThan(matchedCount, 0)

        await MainActor.run {
            controller.submit("", immediate: true)
        }

        let clearedCount = await MainActor.run {
            controller.results.count
        }
        XCTAssertEqual(clearedCount, 0)
    }

    func testControllerCancelStopsSearching() async {
        let items = (0..<30_000).map { i in
            Item(id: i, name: i % 2 == 0 ? "프론트엔드\(i)" : "데이터\(i)")
        }

        let index = HangulSearchIndex(items: items)
        let controller = await MainActor.run {
            HangulSearchController(
                index: index,
                options: .init(
                    debounceMilliseconds: 300,
                    minimumQueryLength: 1,
                    fallbackToSimilarityWhenNoMatch: false
                )
            )
        }

        await MainActor.run {
            controller.submit("ㅍ")
            controller.cancel()
        }

        await wait(milliseconds: 120)

        let searching = await MainActor.run {
            controller.isSearching
        }
        XCTAssertFalse(searching)
    }
}
