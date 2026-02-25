import Foundation
import HangulSearch

public protocol HangulSearchable {
    var hangulSearchKey: String { get }
}

public extension HangulSearchIndex where Item: HangulSearchable {
    convenience init(items: [Item], policy: SearchPolicy = .default) {
        self.init(items: items, keyPath: \.hangulSearchKey, policy: policy)
    }
}
