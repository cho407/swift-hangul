import Foundation

@usableFromInline
internal enum JamoTables {
    @usableFromInline static let choseong: [String] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    @usableFromInline static let jungseong: [String] = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ",
        "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"
    ]

    @usableFromInline static let jongseong: [String] = [
        "", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ",
        "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ",
        "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    @usableFromInline static let doubleVowelDecomposition: [String: (String, String)] = [
        "ㅘ": ("ㅗ", "ㅏ"),
        "ㅙ": ("ㅗ", "ㅐ"),
        "ㅚ": ("ㅗ", "ㅣ"),
        "ㅝ": ("ㅜ", "ㅓ"),
        "ㅞ": ("ㅜ", "ㅔ"),
        "ㅟ": ("ㅜ", "ㅣ"),
        "ㅢ": ("ㅡ", "ㅣ"),
    ]

    @usableFromInline static let doubleFinalDecomposition: [String: (String, String)] = [
        "ㄳ": ("ㄱ", "ㅅ"),
        "ㄵ": ("ㄴ", "ㅈ"),
        "ㄶ": ("ㄴ", "ㅎ"),
        "ㄺ": ("ㄹ", "ㄱ"),
        "ㄻ": ("ㄹ", "ㅁ"),
        "ㄼ": ("ㄹ", "ㅂ"),
        "ㄽ": ("ㄹ", "ㅅ"),
        "ㄾ": ("ㄹ", "ㅌ"),
        "ㄿ": ("ㄹ", "ㅍ"),
        "ㅀ": ("ㄹ", "ㅎ"),
        "ㅄ": ("ㅂ", "ㅅ"),
    ]

    @usableFromInline static let doubleVowelComposition: [String: String] = {
        var result: [String: String] = [:]
        result.reserveCapacity(doubleVowelDecomposition.count)
        for (composed, (left, right)) in doubleVowelDecomposition {
            result[left + right] = composed
        }
        return result
    }()

    @usableFromInline static let doubleFinalComposition: [String: String] = {
        var result: [String: String] = [:]
        result.reserveCapacity(doubleFinalDecomposition.count)
        for (composed, (left, right)) in doubleFinalDecomposition {
            result[left + right] = composed
        }
        return result
    }()

    @usableFromInline static let choseongIndexByJamo: [String: Int] = {
        var map: [String: Int] = [:]
        map.reserveCapacity(choseong.count)
        for (idx, value) in choseong.enumerated() {
            map[value] = idx
        }
        return map
    }()

    @usableFromInline static let jungseongIndexByJamo: [String: Int] = {
        var map: [String: Int] = [:]
        map.reserveCapacity(jungseong.count)
        for (idx, value) in jungseong.enumerated() {
            map[value] = idx
        }
        return map
    }()

    @usableFromInline static let jongseongIndexByJamo: [String: Int] = {
        var map: [String: Int] = [:]
        map.reserveCapacity(jongseong.count)
        for (idx, value) in jongseong.enumerated() {
            map[value] = idx
        }
        return map
    }()

    @usableFromInline static let compatibilityConsonants: Set<String> = [
        "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄸ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ",
        "ㅁ", "ㅂ", "ㅃ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    @usableFromInline static let compatibilityConsonantScalars: Set<UInt32> = {
        var result: Set<UInt32> = []
        result.reserveCapacity(compatibilityConsonants.count)
        for consonant in compatibilityConsonants {
            if let scalar = consonant.unicodeScalars.first {
                result.insert(scalar.value)
            }
        }
        return result
    }()

    @inlinable
    static func isCompatibilityConsonant(_ scalar: UnicodeScalar) -> Bool {
        compatibilityConsonantScalars.contains(scalar.value)
    }

    @inlinable
    static func scalarString(_ scalar: UnicodeScalar) -> String {
        String(scalar)
    }
}
