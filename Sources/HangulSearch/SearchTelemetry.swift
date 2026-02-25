import Foundation

public struct SearchTelemetrySnapshot: Sendable, Equatable {
    public let startedAt: Date
    public let syncSearchCount: Int
    public let asyncSearchSuccessCount: Int
    public let asyncSearchCancelledCount: Int
    public let asyncSearchFailureCount: Int

    public let syncSimilarSearchCount: Int
    public let asyncSimilarSearchSuccessCount: Int
    public let asyncSimilarSearchCancelledCount: Int
    public let asyncSimilarSearchFailureCount: Int

    public let syncExplainCount: Int
    public let asyncExplainSuccessCount: Int
    public let asyncExplainCancelledCount: Int
    public let asyncExplainFailureCount: Int

    public let cacheHitCount: Int
    public let returnedItemCount: Int

    public let meanSyncSearchLatencyMs: Double
    public let meanAsyncSearchLatencyMs: Double
    public let meanSyncSimilarLatencyMs: Double
    public let meanAsyncSimilarLatencyMs: Double
    public let meanSyncExplainLatencyMs: Double
    public let meanAsyncExplainLatencyMs: Double

    public init(
        startedAt: Date,
        syncSearchCount: Int,
        asyncSearchSuccessCount: Int,
        asyncSearchCancelledCount: Int,
        asyncSearchFailureCount: Int,
        syncSimilarSearchCount: Int,
        asyncSimilarSearchSuccessCount: Int,
        asyncSimilarSearchCancelledCount: Int,
        asyncSimilarSearchFailureCount: Int,
        syncExplainCount: Int,
        asyncExplainSuccessCount: Int,
        asyncExplainCancelledCount: Int,
        asyncExplainFailureCount: Int,
        cacheHitCount: Int,
        returnedItemCount: Int,
        meanSyncSearchLatencyMs: Double,
        meanAsyncSearchLatencyMs: Double,
        meanSyncSimilarLatencyMs: Double,
        meanAsyncSimilarLatencyMs: Double,
        meanSyncExplainLatencyMs: Double,
        meanAsyncExplainLatencyMs: Double
    ) {
        self.startedAt = startedAt
        self.syncSearchCount = syncSearchCount
        self.asyncSearchSuccessCount = asyncSearchSuccessCount
        self.asyncSearchCancelledCount = asyncSearchCancelledCount
        self.asyncSearchFailureCount = asyncSearchFailureCount
        self.syncSimilarSearchCount = syncSimilarSearchCount
        self.asyncSimilarSearchSuccessCount = asyncSimilarSearchSuccessCount
        self.asyncSimilarSearchCancelledCount = asyncSimilarSearchCancelledCount
        self.asyncSimilarSearchFailureCount = asyncSimilarSearchFailureCount
        self.syncExplainCount = syncExplainCount
        self.asyncExplainSuccessCount = asyncExplainSuccessCount
        self.asyncExplainCancelledCount = asyncExplainCancelledCount
        self.asyncExplainFailureCount = asyncExplainFailureCount
        self.cacheHitCount = cacheHitCount
        self.returnedItemCount = returnedItemCount
        self.meanSyncSearchLatencyMs = meanSyncSearchLatencyMs
        self.meanAsyncSearchLatencyMs = meanAsyncSearchLatencyMs
        self.meanSyncSimilarLatencyMs = meanSyncSimilarLatencyMs
        self.meanAsyncSimilarLatencyMs = meanAsyncSimilarLatencyMs
        self.meanSyncExplainLatencyMs = meanSyncExplainLatencyMs
        self.meanAsyncExplainLatencyMs = meanAsyncExplainLatencyMs
    }
}

final class SearchTelemetry: @unchecked Sendable {
    private let lock = NSLock()
    private var startedAt = Date()

    private var syncSearchCount = 0
    private var asyncSearchSuccessCount = 0
    private var asyncSearchCancelledCount = 0
    private var asyncSearchFailureCount = 0
    private var cacheHitCount = 0
    private var returnedItemCount = 0
    private var syncSearchTotalLatencyNs: UInt64 = 0
    private var asyncSearchTotalLatencyNs: UInt64 = 0

    private var syncSimilarSearchCount = 0
    private var asyncSimilarSearchSuccessCount = 0
    private var asyncSimilarSearchCancelledCount = 0
    private var asyncSimilarSearchFailureCount = 0
    private var syncSimilarTotalLatencyNs: UInt64 = 0
    private var asyncSimilarTotalLatencyNs: UInt64 = 0

    private var syncExplainCount = 0
    private var asyncExplainSuccessCount = 0
    private var asyncExplainCancelledCount = 0
    private var asyncExplainFailureCount = 0
    private var syncExplainTotalLatencyNs: UInt64 = 0
    private var asyncExplainTotalLatencyNs: UInt64 = 0

    func recordSyncSearch(latencyNs: UInt64, cacheHit: Bool, resultCount: Int) {
        lock.lock()
        syncSearchCount += 1
        if cacheHit { cacheHitCount += 1 }
        returnedItemCount += max(0, resultCount)
        syncSearchTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordAsyncSearchSuccess(latencyNs: UInt64, cacheHit: Bool, resultCount: Int) {
        lock.lock()
        asyncSearchSuccessCount += 1
        if cacheHit { cacheHitCount += 1 }
        returnedItemCount += max(0, resultCount)
        asyncSearchTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordAsyncSearchCancelled(latencyNs: UInt64) {
        lock.lock()
        asyncSearchCancelledCount += 1
        asyncSearchTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordAsyncSearchFailure(latencyNs: UInt64) {
        lock.lock()
        asyncSearchFailureCount += 1
        asyncSearchTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordSyncSimilar(latencyNs: UInt64, resultCount: Int) {
        lock.lock()
        syncSimilarSearchCount += 1
        returnedItemCount += max(0, resultCount)
        syncSimilarTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordAsyncSimilarSuccess(latencyNs: UInt64, resultCount: Int) {
        lock.lock()
        asyncSimilarSearchSuccessCount += 1
        returnedItemCount += max(0, resultCount)
        asyncSimilarTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordAsyncSimilarCancelled(latencyNs: UInt64) {
        lock.lock()
        asyncSimilarSearchCancelledCount += 1
        asyncSimilarTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordAsyncSimilarFailure(latencyNs: UInt64) {
        lock.lock()
        asyncSimilarSearchFailureCount += 1
        asyncSimilarTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordSyncExplain(latencyNs: UInt64, resultCount: Int) {
        lock.lock()
        syncExplainCount += 1
        returnedItemCount += max(0, resultCount)
        syncExplainTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordAsyncExplainSuccess(latencyNs: UInt64, resultCount: Int) {
        lock.lock()
        asyncExplainSuccessCount += 1
        returnedItemCount += max(0, resultCount)
        asyncExplainTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordAsyncExplainCancelled(latencyNs: UInt64) {
        lock.lock()
        asyncExplainCancelledCount += 1
        asyncExplainTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func recordAsyncExplainFailure(latencyNs: UInt64) {
        lock.lock()
        asyncExplainFailureCount += 1
        asyncExplainTotalLatencyNs += latencyNs
        lock.unlock()
    }

    func snapshot() -> SearchTelemetrySnapshot {
        lock.lock()
        defer { lock.unlock() }

        let syncSearchMeanMs = meanMs(totalNs: syncSearchTotalLatencyNs, count: syncSearchCount)
        let asyncSearchMeanMs = meanMs(
            totalNs: asyncSearchTotalLatencyNs,
            count: asyncSearchSuccessCount + asyncSearchCancelledCount + asyncSearchFailureCount
        )
        let syncSimilarMeanMs = meanMs(totalNs: syncSimilarTotalLatencyNs, count: syncSimilarSearchCount)
        let asyncSimilarMeanMs = meanMs(
            totalNs: asyncSimilarTotalLatencyNs,
            count: asyncSimilarSearchSuccessCount + asyncSimilarSearchCancelledCount + asyncSimilarSearchFailureCount
        )
        let syncExplainMeanMs = meanMs(totalNs: syncExplainTotalLatencyNs, count: syncExplainCount)
        let asyncExplainMeanMs = meanMs(
            totalNs: asyncExplainTotalLatencyNs,
            count: asyncExplainSuccessCount + asyncExplainCancelledCount + asyncExplainFailureCount
        )

        return SearchTelemetrySnapshot(
            startedAt: startedAt,
            syncSearchCount: syncSearchCount,
            asyncSearchSuccessCount: asyncSearchSuccessCount,
            asyncSearchCancelledCount: asyncSearchCancelledCount,
            asyncSearchFailureCount: asyncSearchFailureCount,
            syncSimilarSearchCount: syncSimilarSearchCount,
            asyncSimilarSearchSuccessCount: asyncSimilarSearchSuccessCount,
            asyncSimilarSearchCancelledCount: asyncSimilarSearchCancelledCount,
            asyncSimilarSearchFailureCount: asyncSimilarSearchFailureCount,
            syncExplainCount: syncExplainCount,
            asyncExplainSuccessCount: asyncExplainSuccessCount,
            asyncExplainCancelledCount: asyncExplainCancelledCount,
            asyncExplainFailureCount: asyncExplainFailureCount,
            cacheHitCount: cacheHitCount,
            returnedItemCount: returnedItemCount,
            meanSyncSearchLatencyMs: syncSearchMeanMs,
            meanAsyncSearchLatencyMs: asyncSearchMeanMs,
            meanSyncSimilarLatencyMs: syncSimilarMeanMs,
            meanAsyncSimilarLatencyMs: asyncSimilarMeanMs,
            meanSyncExplainLatencyMs: syncExplainMeanMs,
            meanAsyncExplainLatencyMs: asyncExplainMeanMs
        )
    }

    func reset() {
        lock.lock()
        startedAt = Date()
        syncSearchCount = 0
        asyncSearchSuccessCount = 0
        asyncSearchCancelledCount = 0
        asyncSearchFailureCount = 0
        cacheHitCount = 0
        returnedItemCount = 0
        syncSearchTotalLatencyNs = 0
        asyncSearchTotalLatencyNs = 0

        syncSimilarSearchCount = 0
        asyncSimilarSearchSuccessCount = 0
        asyncSimilarSearchCancelledCount = 0
        asyncSimilarSearchFailureCount = 0
        syncSimilarTotalLatencyNs = 0
        asyncSimilarTotalLatencyNs = 0

        syncExplainCount = 0
        asyncExplainSuccessCount = 0
        asyncExplainCancelledCount = 0
        asyncExplainFailureCount = 0
        syncExplainTotalLatencyNs = 0
        asyncExplainTotalLatencyNs = 0
        lock.unlock()
    }

    private func meanMs(totalNs: UInt64, count: Int) -> Double {
        guard count > 0 else { return 0 }
        return Double(totalNs) / Double(count) / 1_000_000.0
    }
}
