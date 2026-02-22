//
//  File.swift
//  swift-hangul
//
//  Created by 조형구 on 2/22/26.
//

import Foundation
import SwiftUI
import HangulSearch

public struct HangulSearchable<Item, Content: View>: View {
    @State private var query: String = ""
    @State private var results: [Item] = []

    private let engine: HangulSearchEngine<Item>
    private let content: (String, [Item]) -> Content

    public init(
        engine: HangulSearchEngine<Item>,
        @ViewBuilder content: @escaping (String, [Item]) -> Content
    ) {
        self.engine = engine
        self.content = content
    }

    public var body: some View {
        content(query, results)
            .searchable(text: $query)
            .onChange(of: query) { _, newValue in
                results = engine.query(newValue)
            }
    }
}
