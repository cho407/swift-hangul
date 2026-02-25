import Foundation

public enum SusaCategory: Sendable {
    case cardinal
    case modifier
}

public struct NumberHangulOptions: Sendable {
    public var spacing: Bool

    public static let `default` = NumberHangulOptions()

    public init(spacing: Bool = false) {
        self.spacing = spacing
    }
}

public extension Hangul {
    static func numberToHangul(_ value: some BinaryInteger, options: NumberHangulOptions = .default) -> String {
        numberToHangul(String(value), options: options)
    }

    static func numberToHangul(_ value: some BinaryFloatingPoint, options: NumberHangulOptions = .default) -> String {
        let doubleValue = Double(value)
        if doubleValue.isNaN { return "영" }
        if doubleValue == Double.infinity { return "무한대" }
        if doubleValue == -Double.infinity {
            return options.spacing ? "마이너스 무한대" : "마이너스무한대"
        }

        return numberToHangul(String(doubleValue), options: options)
    }

    static func numberToHangul(_ raw: String) -> String {
        numberToHangul(raw, options: .default)
    }

    static func numberToHangul(_ raw: String, options: NumberHangulOptions = .default) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let infinite = infinityRepresentation(trimmed, spacing: options.spacing, forMixed: false) {
            return infinite
        }

        guard let parsed = parseDecimalNumber(trimmed) else {
            return "영"
        }

        let intHangul = convertIntegerToHangul(parsed.integerDigits, spacing: options.spacing)
        let hasNonZeroMagnitude = parsed.integerDigits.contains { $0 != "0" } || parsed.fractionDigits.contains { $0 != "0" }
        let signPrefix = (parsed.negative && hasNonZeroMagnitude) ? (options.spacing ? "마이너스 " : "마이너스") : ""

        guard !parsed.fractionDigits.isEmpty else {
            return signPrefix + intHangul
        }

        let decimalDigits = parsed.fractionDigits.compactMap { digitToKorean[$0] }.joined()
        return signPrefix + intHangul + (options.spacing ? "점 " : "점") + decimalDigits
    }

    static func numberToHangulMixed(_ value: some BinaryInteger, options: NumberHangulOptions = .default) -> String {
        numberToHangulMixed(String(value), options: options)
    }

    static func numberToHangulMixed(_ value: some BinaryFloatingPoint, options: NumberHangulOptions = .default) -> String {
        let doubleValue = Double(value)
        if doubleValue.isNaN { return "0" }
        if doubleValue == Double.infinity { return "무한대" }
        if doubleValue == -Double.infinity { return "-무한대" }

        return numberToHangulMixed(String(doubleValue), options: options)
    }

    static func numberToHangulMixed(_ raw: String) -> String {
        numberToHangulMixed(raw, options: .default)
    }

    static func numberToHangulMixed(_ raw: String, options: NumberHangulOptions = .default) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let infinite = infinityRepresentation(trimmed, spacing: options.spacing, forMixed: true) {
            return infinite
        }

        guard let parsed = parseDecimalNumber(trimmed) else {
            return "영"
        }

        var result = convertIntegerToMixed(parsed.integerDigits, spacing: options.spacing)
        if !parsed.fractionDigits.isEmpty {
            result += "." + parsed.fractionDigits
        }

        let hasNonZeroMagnitude = parsed.integerDigits.contains { $0 != "0" } || parsed.fractionDigits.contains { $0 != "0" }
        return (parsed.negative && hasNonZeroMagnitude ? "-" : "") + result
    }

    static func amountToHangul(_ value: some BinaryInteger) -> String {
        amountToHangul(String(value))
    }

    static func amountToHangul(_ raw: String) -> String {
        let sanitized = raw.unicodeScalars.filter { (48...57).contains($0.value) || $0.value == 46 }
        let compact = String(String.UnicodeScalarView(sanitized))
        guard !compact.isEmpty else { return "영" }

        let parts = compact.split(separator: ".", maxSplits: 1).map(String.init)
        let integerPartRaw = parts.first ?? "0"
        let integerPart = integerPartRaw == "0" ? integerPartRaw : String(integerPartRaw.drop { $0 == "0" })
        let decimalPart = parts.count > 1 ? String(parts[1].reversed().drop { $0 == "0" }.reversed()) : ""

        if decimalPart.isEmpty {
            return numberToHangul(integerPart, options: .init(spacing: false))
        }

        return numberToHangul(integerPart + "." + decimalPart, options: .init(spacing: false))
    }

    static func seosusa(_ number: Int) -> String {
        guard number > 0 else { return String(number) }

        if number <= 99 {
            return ordinalWord(number) + "째"
        }

        return numberToHangul(number, options: .init(spacing: false)) + "째"
    }

    static func susa(_ number: Int, category: SusaCategory = .cardinal) -> String {
        guard number >= 1 && number <= 100 else { return String(number) }

        if category == .modifier {
            if number == 20 { return "스무" }

            let tens = (number / 10) * 10
            let ones = number % 10
            let tensWord = nativeCardinal[tens] ?? ""
            if ones == 0 {
                return tensWord
            }

            if let special = nativeModifier[ones] {
                return tensWord + special
            }
            return tensWord + (nativeCardinal[ones] ?? "")
        }

        if number == 100 { return "백" }

        let tens = (number / 10) * 10
        let ones = number % 10
        let tensWord = nativeCardinal[tens] ?? ""

        if ones == 0 { return tensWord }
        return tensWord + (nativeCardinal[ones] ?? "")
    }

    static func days(_ number: Int) -> String {
        guard number >= 1 && number <= 30 else {
            return "\(number)일"
        }

        let tens = (number / 10) * 10
        let ones = number % 10

        if ones == 0, let tensOnly = daysOnlyTens[tens] {
            return tensOnly
        }

        let tensWord = daysMap[tens] ?? ""
        let onesWord = daysMap[ones] ?? ""
        return tensWord + onesWord
    }

    private struct ParsedDecimalNumber {
        let negative: Bool
        let integerDigits: String
        let fractionDigits: String
    }

    private static func parseDecimalNumber(_ input: String) -> ParsedDecimalNumber? {
        var negative = false
        var seenSign = false
        var seenDot = false
        var seenDigit = false

        var integerDigits = String()
        var fractionDigits = String()
        integerDigits.reserveCapacity(input.count)
        fractionDigits.reserveCapacity(input.count)

        for scalar in input.unicodeScalars {
            if scalar.properties.isWhitespace {
                return nil
            }

            if scalar.value == 43 || scalar.value == 45 {
                guard !seenSign, !seenDigit, !seenDot, integerDigits.isEmpty, fractionDigits.isEmpty else {
                    return nil
                }
                seenSign = true
                negative = scalar.value == 45
                continue
            }

            if scalar.value == 46 {
                guard !seenDot else { return nil }
                seenDot = true
                continue
            }

            if scalar.value == 44 || scalar.value == 95 {
                continue
            }

            if (48...57).contains(scalar.value) {
                seenDigit = true
                if seenDot {
                    fractionDigits.unicodeScalars.append(scalar)
                } else {
                    integerDigits.unicodeScalars.append(scalar)
                }
                continue
            }

            return nil
        }

        guard seenDigit else { return nil }
        if integerDigits.isEmpty {
            integerDigits = "0"
        }

        return ParsedDecimalNumber(
            negative: negative,
            integerDigits: integerDigits,
            fractionDigits: fractionDigits
        )
    }

    private static func convertIntegerToHangul(_ integerDigits: String, spacing: Bool) -> String {
        let normalized = integerDigits.drop { $0 == "0" }
        if normalized.isEmpty { return "영" }

        var groups: [String] = []
        groups.reserveCapacity((normalized.count + 3) / 4)
        var index = 0
        var end = normalized.endIndex
        while end > normalized.startIndex {
            let start = normalized.index(end, offsetBy: -min(4, normalized.distance(from: normalized.startIndex, to: end)))
            let chunk = String(normalized[start..<end])
            if let groupHangul = convert4Digits(chunk), !groupHangul.isEmpty {
                groups.append(groupHangul + largeUnit(at: index))
            }
            end = start
            index += 1
        }

        return groups.reversed().joined(separator: spacing ? " " : "")
    }

    private static func convertIntegerToMixed(_ integerDigits: String, spacing: Bool) -> String {
        let normalized = integerDigits.drop { $0 == "0" }
        if normalized.isEmpty { return "0" }

        var groups: [String] = []
        groups.reserveCapacity((normalized.count + 3) / 4)

        var index = 0
        var end = normalized.endIndex
        while end > normalized.startIndex {
            let start = normalized.index(end, offsetBy: -min(4, normalized.distance(from: normalized.startIndex, to: end)))
            let chunk = String(normalized[start..<end])
            if let value = Int(chunk), value != 0 {
                groups.append("\(formatWithComma(value))\(largeUnit(at: index))")
            }
            end = start
            index += 1
        }

        return groups.reversed().joined(separator: spacing ? " " : "")
    }

    private static func convert4Digits(_ chunk: String) -> String? {
        let padded = String(repeating: "0", count: max(0, 4 - chunk.count)) + chunk
        let chars = Array(padded)
        var parts: [String] = []
        parts.reserveCapacity(4)
        for i in 0..<4 {
            guard let n = chars[i].wholeNumberValue else { continue }
            if n == 0 { continue }
            let unit = smallUnits[3 - i]
            if n == 1, !unit.isEmpty {
                parts.append(unit)
            } else {
                parts.append((digitToKorean[chars[i]] ?? "") + unit)
            }
        }

        if parts.isEmpty { return nil }
        return parts.joined()
    }

    private static let smallUnits = ["", "십", "백", "천"]
    private static let largeUnits = [
        "",
        "만",
        "억",
        "조",
        "경",
        "해",
        "자",
        "양",
        "구",
        "간",
        "정",
        "재",
        "극",
        "항하사",
        "아승기",
        "나유타",
        "불가사의",
        "무량대수",
        "겁",
        "업",
    ]

    private static func largeUnit(at index: Int) -> String {
        if index < largeUnits.count {
            return largeUnits[index]
        }
        return "10^\(index * 4)"
    }

    private static func formatWithComma(_ value: Int) -> String {
        let digits = String(value)
        var reversedWithCommas = String()
        reversedWithCommas.reserveCapacity(digits.count + digits.count / 3)

        var groupCount = 0
        for scalar in digits.unicodeScalars.reversed() {
            if groupCount == 3 {
                reversedWithCommas.append(",")
                groupCount = 0
            }
            reversedWithCommas.unicodeScalars.append(scalar)
            groupCount += 1
        }

        return String(reversedWithCommas.reversed())
    }

    private static let digitToKorean: [Character: String] = [
        "0": "영", "1": "일", "2": "이", "3": "삼", "4": "사", "5": "오", "6": "육", "7": "칠", "8": "팔", "9": "구"
    ]

    private static let nativeCardinal: [Int: String] = [
        1: "하나", 2: "둘", 3: "셋", 4: "넷", 5: "다섯", 6: "여섯", 7: "일곱", 8: "여덟", 9: "아홉", 10: "열",
        20: "스물", 30: "서른", 40: "마흔", 50: "쉰", 60: "예순", 70: "일흔", 80: "여든", 90: "아흔",
        100: "백"
    ]

    private static let nativeModifier: [Int: String] = [
        1: "한", 2: "두", 3: "세", 4: "네", 20: "스무"
    ]

    private static let daysMap: [Int: String] = [
        1: "하루", 2: "이틀", 3: "사흘", 4: "나흘", 5: "닷새", 6: "엿새", 7: "이레", 8: "여드레", 9: "아흐레",
        10: "열", 20: "스무"
    ]

    private static let daysOnlyTens: [Int: String] = [
        10: "열흘",
        20: "스무날",
        30: "서른날"
    ]

    private static let ordinalBase: [Int: String] = [
        1: "한", 2: "두", 3: "셋", 4: "넷", 5: "다섯", 6: "여섯", 7: "일곱", 8: "여덟", 9: "아홉",
        10: "열", 20: "스물", 30: "서른", 40: "마흔", 50: "쉰", 60: "예순", 70: "일흔", 80: "여든", 90: "아흔"
    ]

    private static let ordinalSpecial: [Int: String] = [
        1: "첫",
        2: "둘",
        20: "스무"
    ]

    private static func ordinalWord(_ number: Int) -> String {
        if let special = ordinalSpecial[number] {
            return special
        }

        let tens = (number / 10) * 10
        let ones = number % 10

        let tensWord = ordinalBase[tens] ?? ""
        let onesWord = ordinalBase[ones] ?? ""
        return tensWord + onesWord
    }

    private static func infinityRepresentation(_ input: String, spacing: Bool, forMixed: Bool) -> String? {
        let lower = input.lowercased()
        switch lower {
        case "infinity", "+infinity", "inf", "+inf":
            return "무한대"
        case "-infinity", "-inf":
            if forMixed {
                return "-무한대"
            }
            return spacing ? "마이너스 무한대" : "마이너스무한대"
        default:
            return nil
        }
    }
}
