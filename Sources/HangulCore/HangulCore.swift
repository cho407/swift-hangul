//
//  File.swift
//  swift-hangul
//
//  Created by 조형구 on 2/22/26.
//

import Foundation

public enum HangulCore {
    public static func normalize(_ s: String) -> String {
        // MVP: 추후 NFKC/NFC + 공백/특수문자 규칙 확장
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
