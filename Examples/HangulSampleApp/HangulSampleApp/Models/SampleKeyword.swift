import Foundation

struct SampleKeyword: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let subtitle: String
    let tags: [String]
    
    var hangulSearchKey: String {
        ([title, subtitle] + tags).joined(separator: " ")
    }
}

