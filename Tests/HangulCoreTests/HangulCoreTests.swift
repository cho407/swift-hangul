//
//  File.swift
//  swift-hangul
//
//  Created by 조형구 on 2/22/26.
//

import XCTest
@testable import HangulCore

final class HangulCoreTests: XCTestCase {
    func testNormalizeTrims() {
        XCTAssertEqual(HangulCore.normalize("  가나  "), "가나")
    }
}
