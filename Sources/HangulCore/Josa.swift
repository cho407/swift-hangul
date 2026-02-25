import Foundation

public enum JosaPair: String, Sendable {
    case subject = "이/가"
    case object = "을/를"
    case topic = "은/는"
    case withInstrumental = "으로/로"
    case and = "와/과"
    case or = "이나/나"
    case quote = "이란/란"
    case vocative = "아/야"
    case with = "이랑/랑"
    case politeCopula = "이에요/예요"
    case status = "으로서/로서"
    case by = "으로써/로써"
    case from = "으로부터/로부터"
    case copula = "이라/라"

    fileprivate var parts: (String, String) {
        let tokens = rawValue.split(separator: "/", maxSplits: 1).map(String.init)
        if tokens.count == 2 {
            return (tokens[0], tokens[1])
        }
        return (rawValue, rawValue)
    }

    fileprivate var supportsRieulRoRule: Bool {
        switch self {
        case .withInstrumental, .status, .by, .from:
            return true
        default:
            return false
        }
    }
}

public extension Hangul {
    static func josa(_ word: String, _ pair: JosaPair) -> String {
        guard !word.isEmpty else { return word }
        let normalized = normalizeForAcronym(word)
        return word + pickJosa(normalized, pair)
    }

    static func josa(_ word: String, _ pair: String) -> String {
        guard !word.isEmpty else { return word }
        let normalized = normalizeForAcronym(word)
        return word + pickJosa(normalized, pair)
    }

    static func pickJosa(_ word: String, _ pair: JosaPair) -> String {
        let parts = pair.parts
        guard !word.isEmpty else { return parts.0 }

        let ending = endingSoundInfo(for: word)
        var index = ending.hasBatchim ? 0 : 1

        if pair == .and {
            index = 1 - index
        }

        if ending.hasBatchim, ending.isRieul, pair.supportsRieulRoRule {
            index = 1
        }

        return index == 0 ? parts.0 : parts.1
    }

    static func pickJosa(_ word: String, _ pair: String) -> String {
        if let builtIn = JosaPair(rawValue: pair) {
            return pickJosa(word, builtIn)
        }

        let parts = pair.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return pair }
        guard !word.isEmpty else { return parts[0] }

        let ending = endingSoundInfo(for: word)
        return ending.hasBatchim ? parts[0] : parts[1]
    }

    private struct EndingSoundInfo {
        let hasBatchim: Bool
        let isRieul: Bool
    }

    private static func endingSoundInfo(for word: String) -> EndingSoundInfo {
        let scalars = Array(word.unicodeScalars)
        var end = scalars.count
        while end > 0, isIgnorableTail(scalars[end - 1]) {
            end -= 1
        }

        guard end > 0 else {
            return .init(hasBatchim: false, isRieul: false)
        }

        let last = scalars[end - 1]

        if let components = UnicodeHangul.decompose(last) {
            if components.t == 0 {
                return .init(hasBatchim: false, isRieul: false)
            }
            let final = JamoTables.jongseong[components.t]
            return .init(hasBatchim: true, isRieul: final == "ㄹ")
        }

        let token = String(last)
        if let tIndex = JamoTables.jongseongIndexByJamo[token], tIndex > 0 {
            return .init(hasBatchim: true, isRieul: token == "ㄹ")
        }

        if let vIndex = JamoTables.jungseongIndexByJamo[token], vIndex >= 0 {
            return .init(hasBatchim: false, isRieul: false)
        }

        if last.isASCII {
            let digit = Character(String(last))
            if let info = digitEndingSound[digit] {
                return info
            }
        }

        if last.isASCII, isASCIIAlphabet(last) {
            let trailingWord = trailingASCIIWord(scalars: scalars, end: end)
            if !trailingWord.isEmpty {
                if trailingWord == trailingWord.uppercased(),
                   let acronymLast = trailingWord.last,
                   let info = acronymEndingSound[acronymLast] {
                    return info
                }

                let lower = trailingWord.lowercased()
                if lower.hasSuffix("ng") {
                    return .init(hasBatchim: true, isRieul: false)
                }

                if let lastChar = lower.last {
                    if lastChar == "l" || lastChar == "r" {
                        return .init(hasBatchim: true, isRieul: true)
                    }
                    if lastChar == "m" || lastChar == "n" {
                        return .init(hasBatchim: true, isRieul: false)
                    }
                }
            }
        }

        return .init(hasBatchim: false, isRieul: false)
    }

    private static func trailingASCIIWord(scalars: [UnicodeScalar], end: Int) -> String {
        var start = end
        while start > 0, isASCIIAlphabet(scalars[start - 1]) {
            start -= 1
        }

        guard start < end else { return "" }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    private static func isASCIIAlphabet(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        return (65...90).contains(v) || (97...122).contains(v)
    }

    private static func normalizeForAcronym(_ word: String) -> String {
        guard !word.isEmpty,
              word.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }),
              let last = word.last,
              let korean = alphabetToKorean[last] else {
            return word
        }
        return korean
    }

    private static func isIgnorableTail(_ scalar: UnicodeScalar) -> Bool {
        if scalar.properties.isWhitespace { return true }

        switch scalar.properties.generalCategory {
        case .connectorPunctuation,
             .dashPunctuation,
             .openPunctuation,
             .closePunctuation,
             .initialPunctuation,
             .finalPunctuation,
             .otherPunctuation,
             .mathSymbol,
             .currencySymbol,
             .modifierSymbol,
             .otherSymbol:
            return true
        default:
            return false
        }
    }

    private static let digitEndingSound: [Character: EndingSoundInfo] = [
        "0": .init(hasBatchim: false, isRieul: false),
        "1": .init(hasBatchim: true, isRieul: true),
        "2": .init(hasBatchim: false, isRieul: false),
        "3": .init(hasBatchim: true, isRieul: false),
        "4": .init(hasBatchim: false, isRieul: false),
        "5": .init(hasBatchim: false, isRieul: false),
        "6": .init(hasBatchim: true, isRieul: false),
        "7": .init(hasBatchim: true, isRieul: true),
        "8": .init(hasBatchim: true, isRieul: true),
        "9": .init(hasBatchim: false, isRieul: false),
    ]

    private static let acronymEndingSound: [Character: EndingSoundInfo] = [
        "A": .init(hasBatchim: false, isRieul: false),
        "B": .init(hasBatchim: false, isRieul: false),
        "C": .init(hasBatchim: false, isRieul: false),
        "D": .init(hasBatchim: false, isRieul: false),
        "E": .init(hasBatchim: false, isRieul: false),
        "F": .init(hasBatchim: true, isRieul: false),
        "G": .init(hasBatchim: false, isRieul: false),
        "H": .init(hasBatchim: false, isRieul: false),
        "I": .init(hasBatchim: false, isRieul: false),
        "J": .init(hasBatchim: false, isRieul: false),
        "K": .init(hasBatchim: false, isRieul: false),
        "L": .init(hasBatchim: true, isRieul: true),
        "M": .init(hasBatchim: true, isRieul: false),
        "N": .init(hasBatchim: true, isRieul: false),
        "O": .init(hasBatchim: false, isRieul: false),
        "P": .init(hasBatchim: false, isRieul: false),
        "Q": .init(hasBatchim: false, isRieul: false),
        "R": .init(hasBatchim: true, isRieul: true),
        "S": .init(hasBatchim: false, isRieul: false),
        "T": .init(hasBatchim: false, isRieul: false),
        "U": .init(hasBatchim: false, isRieul: false),
        "V": .init(hasBatchim: false, isRieul: false),
        "W": .init(hasBatchim: false, isRieul: false),
        "X": .init(hasBatchim: false, isRieul: false),
        "Y": .init(hasBatchim: false, isRieul: false),
        "Z": .init(hasBatchim: false, isRieul: false),
    ]

    private static let alphabetToKorean: [Character: String] = [
        "A": "에이",
        "B": "비",
        "C": "씨",
        "D": "디",
        "E": "이",
        "F": "에프",
        "G": "지",
        "H": "에이치",
        "I": "아이",
        "J": "제이",
        "K": "케이",
        "L": "엘",
        "M": "엠",
        "N": "엔",
        "O": "오",
        "P": "피",
        "Q": "큐",
        "R": "알",
        "S": "에스",
        "T": "티",
        "U": "유",
        "V": "브이",
        "W": "더블유",
        "X": "엑스",
        "Y": "와이",
        "Z": "지",
    ]
}
