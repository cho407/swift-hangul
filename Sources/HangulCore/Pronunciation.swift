import Foundation

public struct PronunciationOptions: Sendable {
    public var applyPalatalization: Bool
    public var applyLiaison: Bool
    public var applyHieutRule: Bool
    public var applyObstruentBeforeHieut: Bool
    public var applyNasalization: Bool
    public var applyLateralization: Bool
    public var applyTensification: Bool
    public var applyNeutralization: Bool

    public static let `default` = PronunciationOptions()

    public init(
        applyPalatalization: Bool = true,
        applyLiaison: Bool = true,
        applyHieutRule: Bool = true,
        applyObstruentBeforeHieut: Bool = true,
        applyNasalization: Bool = true,
        applyLateralization: Bool = true,
        applyTensification: Bool = true,
        applyNeutralization: Bool = true
    ) {
        self.applyPalatalization = applyPalatalization
        self.applyLiaison = applyLiaison
        self.applyHieutRule = applyHieutRule
        self.applyObstruentBeforeHieut = applyObstruentBeforeHieut
        self.applyNasalization = applyNasalization
        self.applyLateralization = applyLateralization
        self.applyTensification = applyTensification
        self.applyNeutralization = applyNeutralization
    }
}

public enum RomanizeStrategy: Sendable {
    case pronunciation
    case literal
}

public enum RomanizeCasing: Sendable {
    case lowercase
    case uppercase
}

public struct RomanizeOptions: Sendable {
    public var strategy: RomanizeStrategy
    public var casing: RomanizeCasing

    public static let `default` = RomanizeOptions()

    public init(strategy: RomanizeStrategy = .pronunciation, casing: RomanizeCasing = .lowercase) {
        self.strategy = strategy
        self.casing = casing
    }
}

public extension Hangul {
    static func standardizePronunciation(_ input: String, hardConversion: Bool) -> String {
        var options = PronunciationOptions.default
        options.applyTensification = hardConversion
        return standardizePronunciation(input, options: options)
    }

    static func standardizePronunciation(_ input: String, options: PronunciationOptions = .default) -> String {
        if input.isEmpty {
            return ""
        }

        if let exception = pronunciationExceptions[input] {
            return exception
        }

        let normalized = input.precomposedStringWithCanonicalMapping
        var units = normalized.unicodeScalars.map { scalar -> SyllableUnit in
            if let parts = UnicodeHangul.decompose(scalar) {
                return .hangul(.init(l: parts.l, v: parts.v, t: parts.t))
            }
            return .other(String(scalar))
        }

        guard units.count > 1 else { return normalized }

        for i in 0..<(units.count - 1) {
            guard case var .hangul(current) = units[i],
                  case var .hangul(next) = units[i + 1] else {
                continue
            }

            if options.applyTensification {
                applyTensification(current: &current, next: &next)
            }
            if options.applyPalatalization {
                applyPalatalization(current: &current, next: &next)
            }
            applyNLRieulInsertion(current: &current, next: &next)
            if options.applyNasalization {
                applyRieulToNieunAssimilation(current: &current, next: &next)
                applyNasalization(current: &current, next: &next)
            }
            if options.applyLateralization {
                applyLateralization(current: &current, next: &next)
            }
            if options.applyHieutRule {
                applyHieutRule(current: &current, next: &next)
            }
            if options.applyObstruentBeforeHieut {
                applyObstruentBeforeHieut(current: &current, next: &next)
            }
            if options.applyLiaison {
                applyLiaison(current: &current, next: &next)
            }

            units[i] = .hangul(current)
            units[i + 1] = .hangul(next)
        }

        if options.applyNeutralization {
            for i in units.indices {
                guard case var .hangul(current) = units[i] else { continue }

                let nextIsVowelCarrier: Bool = {
                    guard i + 1 < units.count,
                          case let .hangul(next) = units[i + 1] else {
                        return false
                    }
                    return JamoTables.choseong[next.l] == "ㅇ"
                }()

                if !nextIsVowelCarrier {
                    current.t = neutralizedJongseongIndex(current.t)
                }
                units[i] = .hangul(current)
            }
        }

        var result = String()
        result.reserveCapacity(input.count)

        for unit in units {
            switch unit {
            case let .hangul(syllable):
                if let scalar = UnicodeHangul.compose(l: syllable.l, v: syllable.v, t: syllable.t) {
                    result.unicodeScalars.append(scalar)
                }
            case let .other(raw):
                result.append(raw)
            }
        }

        return result
    }

    static func romanize(_ input: String) -> String {
        romanize(input, options: .default)
    }

    static func romanize(_ input: String, options: RomanizeOptions = .default) -> String {
        let source: String
        switch options.strategy {
        case .pronunciation:
            source = standardizePronunciation(input, hardConversion: false)
        case .literal:
            source = input.precomposedStringWithCanonicalMapping
        }

        var result = String()
        result.reserveCapacity(source.count * 2)
        var previousFinalJamo: String?
        var previousWasHangul = false

        for scalar in source.unicodeScalars {
            guard let components = UnicodeHangul.decompose(scalar) else {
                let token = String(scalar)
                if let lIndex = JamoTables.choseongIndexByJamo[token] {
                    result.append(choseongRomanization[lIndex])
                } else if let vIndex = JamoTables.jungseongIndexByJamo[token] {
                    result.append(jungseongRomanization[vIndex])
                } else {
                    result.append(token)
                }
                previousWasHangul = false
                previousFinalJamo = nil
                continue
            }

            let onset = onsetRomanization(
                l: components.l,
                previousFinalJamo: previousFinalJamo,
                previousWasHangul: previousWasHangul
            )
            result.append(onset + jungseongRomanization[components.v] + jongseongRomanization[components.t])

            previousWasHangul = true
            previousFinalJamo = JamoTables.jongseong[components.t]
        }

        switch options.casing {
        case .lowercase:
            return result
        case .uppercase:
            return result.uppercased()
        }
    }

    private enum SyllableUnit {
        case hangul(Syllable)
        case other(String)
    }

    private struct Syllable {
        var l: Int
        var v: Int
        var t: Int
    }

    private static func applyPalatalization(current: inout Syllable, next: inout Syllable) {
        let currentFinal = JamoTables.jongseong[current.t]
        let nextInitial = JamoTables.choseong[next.l]
        let nextVowel = JamoTables.jungseong[next.v]

        guard nextVowel == "ㅣ" else { return }

        if nextInitial == "ㅇ", currentFinal == "ㄷ" {
            current.t = 0
            next.l = JamoTables.choseongIndexByJamo["ㅈ"] ?? next.l
        } else if nextInitial == "ㅇ", currentFinal == "ㅌ" {
            current.t = 0
            next.l = JamoTables.choseongIndexByJamo["ㅊ"] ?? next.l
        } else if nextInitial == "ㅇ", currentFinal == "ㄾ" {
            current.t = JamoTables.jongseongIndexByJamo["ㄹ"] ?? current.t
            next.l = JamoTables.choseongIndexByJamo["ㅊ"] ?? next.l
        } else if nextInitial == "ㅎ", currentFinal == "ㄷ" {
            current.t = 0
            next.l = JamoTables.choseongIndexByJamo["ㅊ"] ?? next.l
        }
    }

    private static func applyLiaison(current: inout Syllable, next: inout Syllable) {
        guard current.t > 0, JamoTables.choseong[next.l] == "ㅇ" else { return }

        let finalJamo = JamoTables.jongseong[current.t]
        guard finalJamo != "ㅇ" else { return }

        if let split = JamoTables.doubleFinalDecomposition[finalJamo] {
            current.t = JamoTables.jongseongIndexByJamo[split.0] ?? current.t
            let movedJamo = split.1 == "ㅅ" ? "ㅆ" : split.1
            if let movedL = JamoTables.choseongIndexByJamo[movedJamo] {
                next.l = movedL
            }
            return
        }

        guard let movedL = JamoTables.choseongIndexByJamo[finalJamo] else { return }
        current.t = 0
        next.l = movedL
    }

    private static func applyHieutRule(current: inout Syllable, next: inout Syllable) {
        guard current.t > 0 else { return }

        let finalJamo = JamoTables.jongseong[current.t]
        let nextInitial = JamoTables.choseong[next.l]

        let aspirationMap: [String: String] = ["ㄱ": "ㅋ", "ㄷ": "ㅌ", "ㅈ": "ㅊ", "ㅅ": "ㅆ"]

        if finalJamo == "ㅎ" {
            if let aspirated = aspirationMap[nextInitial], let idx = JamoTables.choseongIndexByJamo[aspirated] {
                current.t = 0
                next.l = idx
                return
            }
            if nextInitial == "ㄴ" {
                current.t = JamoTables.jongseongIndexByJamo["ㄴ"] ?? current.t
                return
            }
        }

        if let split = JamoTables.doubleFinalDecomposition[finalJamo], split.1 == "ㅎ" {
            if let aspirated = aspirationMap[nextInitial],
               let aspiratedL = JamoTables.choseongIndexByJamo[aspirated],
               let keptT = JamoTables.jongseongIndexByJamo[split.0] {
                current.t = keptT
                next.l = aspiratedL
                return
            }

            if nextInitial == "ㄴ", let keptT = JamoTables.jongseongIndexByJamo[split.0] {
                current.t = keptT
            }
        }
    }

    private static func applyObstruentBeforeHieut(current: inout Syllable, next: inout Syllable) {
        guard current.t > 0, JamoTables.choseong[next.l] == "ㅎ" else { return }

        let finalJamo = JamoTables.jongseong[current.t]
        let map: [String: String] = ["ㄱ": "ㅋ", "ㄷ": "ㅌ", "ㅂ": "ㅍ", "ㅈ": "ㅊ"]

        guard let aspirated = map[finalJamo],
              let newL = JamoTables.choseongIndexByJamo[aspirated] else { return }

        current.t = 0
        next.l = newL
    }

    private static func applyNasalization(current: inout Syllable, next: inout Syllable) {
        guard current.t > 0 else { return }

        let nextInitial = JamoTables.choseong[next.l]
        guard nextInitial == "ㄴ" || nextInitial == "ㅁ" else { return }

        let finalJamo = JamoTables.jongseong[current.t]
        let map: [String: String] = [
            "ㄱ": "ㅇ", "ㄲ": "ㅇ", "ㅋ": "ㅇ", "ㄳ": "ㅇ", "ㄺ": "ㅇ",
            "ㄷ": "ㄴ", "ㅅ": "ㄴ", "ㅆ": "ㄴ", "ㅈ": "ㄴ", "ㅊ": "ㄴ", "ㅌ": "ㄴ", "ㅎ": "ㄴ",
            "ㅂ": "ㅁ", "ㅍ": "ㅁ", "ㅄ": "ㅁ", "ㄼ": "ㅁ", "ㄿ": "ㅁ"
        ]

        guard let changed = map[finalJamo], let idx = JamoTables.jongseongIndexByJamo[changed] else { return }
        current.t = idx
    }

    private static func applyRieulToNieunAssimilation(current: inout Syllable, next: inout Syllable) {
        guard current.t > 0, JamoTables.choseong[next.l] == "ㄹ" else { return }
        guard rieulToNieunFinals.contains(JamoTables.jongseong[current.t]) else { return }
        next.l = JamoTables.choseongIndexByJamo["ㄴ"] ?? next.l
    }

    private static func applyLateralization(current: inout Syllable, next: inout Syllable) {
        guard current.t > 0 else { return }

        let finalJamo = JamoTables.jongseong[current.t]
        let nextInitial = JamoTables.choseong[next.l]

        if finalJamo == "ㄴ", nextInitial == "ㄹ" {
            current.t = JamoTables.jongseongIndexByJamo["ㄹ"] ?? current.t
            next.l = JamoTables.choseongIndexByJamo["ㄹ"] ?? next.l
            return
        }

        if finalJamo == "ㄹ", nextInitial == "ㄴ" {
            next.l = JamoTables.choseongIndexByJamo["ㄹ"] ?? next.l
        }
    }

    private static func applyTensification(current: inout Syllable, next: inout Syllable) {
        guard current.t > 0 else { return }

        let triggerFinals: Set<String> = ["ㄱ", "ㄲ", "ㅋ", "ㄳ", "ㄺ", "ㄷ", "ㅅ", "ㅆ", "ㅈ", "ㅊ", "ㅌ", "ㅂ", "ㅍ", "ㄼ", "ㄿ", "ㅄ"]
        let nextInitial = JamoTables.choseong[next.l]
        let tenseMap: [String: String] = ["ㄱ": "ㄲ", "ㄷ": "ㄸ", "ㅂ": "ㅃ", "ㅅ": "ㅆ", "ㅈ": "ㅉ"]

        guard triggerFinals.contains(JamoTables.jongseong[current.t]),
              let tense = tenseMap[nextInitial],
              let tenseL = JamoTables.choseongIndexByJamo[tense] else {
            return
        }

        next.l = tenseL
    }

    private static func applyNLRieulInsertion(current: inout Syllable, next: inout Syllable) {
        guard current.t > 0, JamoTables.choseong[next.l] == "ㅇ" else { return }

        let nextVowel = JamoTables.jungseong[next.v]
        guard nlInsertionFollowingVowels.contains(nextVowel) else { return }

        let finalJamo = JamoTables.jongseong[current.t]
        let isIEscape = nextVowel == "ㅣ" && next.t == 0 && !complexFinalsForSimplification.contains(finalJamo)
        if isIEscape {
            return
        }

        let currentVowel = JamoTables.jungseong[current.v]
        if nlInsertionSimpleVowels.contains(currentVowel) {
            if nlInsertionNieunFinals.contains(finalJamo) {
                if finalJamo == "ㄱ" {
                    current.t = JamoTables.jongseongIndexByJamo["ㅇ"] ?? current.t
                }
                next.l = JamoTables.choseongIndexByJamo["ㄴ"] ?? next.l
            } else if finalJamo == "ㄹ" {
                next.l = JamoTables.choseongIndexByJamo["ㄹ"] ?? next.l
            }
            return
        }

        if let simplified = simplifiedComplexFinalMap[finalJamo],
           let simplifiedT = JamoTables.jongseongIndexByJamo[simplified] {
            current.t = simplifiedT
            return
        }

        if let movedL = JamoTables.choseongIndexByJamo[finalJamo] {
            next.l = movedL
        }
    }

    private static func neutralizedJongseongIndex(_ t: Int) -> Int {
        guard t > 0 else { return 0 }

        let final = JamoTables.jongseong[t]
        let neutralMap: [String: String] = [
            "ㄲ": "ㄱ", "ㅋ": "ㄱ", "ㄳ": "ㄱ", "ㄺ": "ㄱ",
            "ㅅ": "ㄷ", "ㅆ": "ㄷ", "ㅈ": "ㄷ", "ㅊ": "ㄷ", "ㅌ": "ㄷ", "ㅎ": "ㄷ",
            "ㄵ": "ㄴ", "ㄶ": "ㄴ",
            "ㄻ": "ㅁ",
            "ㄼ": "ㅂ", "ㄿ": "ㅂ", "ㅄ": "ㅂ", "ㅍ": "ㅂ",
            "ㄽ": "ㄹ", "ㄾ": "ㄹ", "ㅀ": "ㄹ"
        ]

        guard let normalized = neutralMap[final] else { return t }
        return JamoTables.jongseongIndexByJamo[normalized] ?? t
    }

    private static let choseongRomanization: [String] = [
        "g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"
    ]

    private static let jungseongRomanization: [String] = [
        "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"
    ]

    private static let jongseongRomanization: [String] = [
        "", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m", "p", "l", "l", "p", "l", "m", "p", "p", "t", "t", "ng", "t", "t", "k", "t", "p", "t"
    ]

    private static func onsetRomanization(l: Int, previousFinalJamo: String?, previousWasHangul: Bool) -> String {
        let onset = JamoTables.choseong[l]
        if onset != "ㄹ" {
            return choseongRomanization[l]
        }

        if previousWasHangul, previousFinalJamo == "ㄹ" {
            return "l"
        }

        return "r"
    }

    private static let pronunciationExceptions: [String: String] = [
        "베갯잇": "베갠닏",
        "깻잎": "깬닙",
        "나뭇잎": "나문닙",
        "도리깻열": "도리깬녈",
        "뒷윷": "뒨뉻",
        "전역": "저녁",
    ]

    private static let rieulToNieunFinals: Set<String> = ["ㅁ", "ㅇ", "ㄱ", "ㅂ"]
    private static let nlInsertionSimpleVowels: Set<String> = ["ㅏ", "ㅐ", "ㅓ", "ㅔ", "ㅗ", "ㅜ", "ㅟ"]
    private static let nlInsertionFollowingVowels: Set<String> = ["ㅑ", "ㅕ", "ㅛ", "ㅠ", "ㅣ", "ㅒ", "ㅖ"]
    private static let nlInsertionNieunFinals: Set<String> = ["ㄱ", "ㄴ", "ㄷ", "ㅁ", "ㅂ", "ㅇ"]
    private static let complexFinalsForSimplification: Set<String> = [
        "ㄳ", "ㄵ", "ㄶ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅄ"
    ]
    private static let simplifiedComplexFinalMap: [String: String] = [
        "ㄳ": "ㄱ",
        "ㄵ": "ㄴ",
        "ㄶ": "ㄴ",
        "ㄺ": "ㄱ",
        "ㄻ": "ㅁ",
        "ㄼ": "ㄹ",
        "ㄽ": "ㄹ",
        "ㄾ": "ㄹ",
        "ㄿ": "ㄹ",
        "ㅀ": "ㄹ",
        "ㅄ": "ㅂ",
    ]
}
