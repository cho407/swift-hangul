//
//  File.swift
//  swift-hangul
//
//  Created by 조형구 on 2/22/26.
//

import Foundation

import HangulCore

public struct HangulSearchEngine<Item> {
    public typealias ExtractText = (Item) -> String

    private let items: [Item]
    private let textOf: ExtractText

    public init(items: [Item], textOf: @escaping ExtractText) {
        self.items = items
        self.textOf = textOf
    }

    public func query(_ q: String, topK: Int = 20) -> [Item] {
        let nq = HangulCore.normalize(q)
        guard !nq.isEmpty else { return [] }
        return items
            .filter { HangulCore.normalize(textOf($0)).contains(nq) }
            .prefix(max(0, topK))
            .map { $0 }
    }
}
