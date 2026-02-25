import Foundation
import HangulCore

final class LazyKeyMaterializer: @unchecked Sendable {
    private enum State {
        case empty
        case building
        case ready([String])
    }

    private var state: State = .empty
    private let condition = NSCondition()

    func startBackgroundBuild(rawKeys: [String], options: ChoseongOptions) {
        condition.lock()
        if case .empty = state {
            state = .building
            condition.unlock()

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let built = Self.buildKeys(rawKeys: rawKeys, options: options)
                self.storeBuiltKeysIfNeeded(built)
            }
            return
        }
        condition.unlock()
    }

    func readyKeys() -> [String]? {
        condition.lock()
        defer { condition.unlock() }

        if case let .ready(keys) = state {
            return keys
        }
        return nil
    }

    func getOrBuild(rawKeys: [String], options: ChoseongOptions) -> [String] {
        condition.lock()

        while true {
            switch state {
            case let .ready(keys):
                condition.unlock()
                return keys
            case .building:
                condition.wait()
            case .empty:
                state = .building
                condition.unlock()

                let built = Self.buildKeys(rawKeys: rawKeys, options: options)
                storeBuiltKeysIfNeeded(built)
                return built
            }
        }
    }

    func storeBuiltKeysIfNeeded(_ keys: [String]) {
        condition.lock()
        defer { condition.unlock() }

        if case .ready = state {
            return
        }

        state = .ready(keys)
        condition.broadcast()
    }

    private static func buildKeys(rawKeys: [String], options: ChoseongOptions) -> [String] {
        rawKeys.map { Hangul.getChoseong($0, options: options) }
    }
}
