import Foundation

public enum BatchimKind: Sendable {
    case single
    case double
}

public struct BatchimOptions: Sendable {
    public var only: BatchimKind?
    public var strictCompleteSyllableOnly: Bool

    public static let `default` = BatchimOptions(only: nil, strictCompleteSyllableOnly: false)

    public init(only: BatchimKind? = nil, strictCompleteSyllableOnly: Bool = false) {
        self.only = only
        self.strictCompleteSyllableOnly = strictCompleteSyllableOnly
    }
}

public struct DisassembleOptions: Sendable {
    public var decomposeDoubleVowels: Bool
    public var decomposeDoubleFinals: Bool
    public var preserveNonHangul: Bool

    public static let `default` = DisassembleOptions(
        decomposeDoubleVowels: true,
        decomposeDoubleFinals: true,
        preserveNonHangul: true
    )

    public init(
        decomposeDoubleVowels: Bool = true,
        decomposeDoubleFinals: Bool = true,
        preserveNonHangul: Bool = true
    ) {
        self.decomposeDoubleVowels = decomposeDoubleVowels
        self.decomposeDoubleFinals = decomposeDoubleFinals
        self.preserveNonHangul = preserveNonHangul
    }
}

public enum WhitespacePolicy: Sendable {
    case keep
    case normalize
    case remove
}

public struct ChoseongOptions: Sendable {
    public var preserveNonHangul: Bool
    public var whitespacePolicy: WhitespacePolicy

    public static let `default` = ChoseongOptions(preserveNonHangul: true, whitespacePolicy: .keep)
    public static let esHangul = ChoseongOptions(preserveNonHangul: false, whitespacePolicy: .keep)

    public init(preserveNonHangul: Bool = true, whitespacePolicy: WhitespacePolicy = .keep) {
        self.preserveNonHangul = preserveNonHangul
        self.whitespacePolicy = whitespacePolicy
    }
}

public struct HangulCharacterComponents: Sendable, Equatable {
    public let choseong: String
    public let jungseong: String
    public let jongseong: String

    public init(choseong: String, jungseong: String, jongseong: String) {
        self.choseong = choseong
        self.jungseong = jungseong
        self.jongseong = jongseong
    }
}

public enum HangulCoreError: Error, Sendable {
    case invalidHangulComponents(choseong: String, jungseong: String, jongseong: String)
}

public enum Hangul {
    public static let choseongs: [String] = JamoTables.choseong
    public static let jungseongs: [String] = JamoTables.jungseong
    public static let jongseongs: [String] = JamoTables.jongseong

    public static func disassemble(_ str: String, options: DisassembleOptions = .default) -> String {
        DisassembleEngine.disassemble(str, options: options)
    }

    public static func disassembleToGroups(
        _ str: String,
        options: DisassembleOptions = .default
    ) -> [[String]] {
        var result: [[String]] = []
        result.reserveCapacity(str.count)

        for scalar in str.unicodeScalars {
            if let components = UnicodeHangul.decompose(scalar) {
                var group: [String] = []
                group.reserveCapacity(4)
                group.append(JamoTables.choseong[components.l])

                let vowel = JamoTables.jungseong[components.v]
                if options.decomposeDoubleVowels, let split = JamoTables.doubleVowelDecomposition[vowel] {
                    group.append(split.0)
                    group.append(split.1)
                } else {
                    group.append(vowel)
                }

                if components.t > 0 {
                    let final = JamoTables.jongseong[components.t]
                    if options.decomposeDoubleFinals, let split = JamoTables.doubleFinalDecomposition[final] {
                        group.append(split.0)
                        group.append(split.1)
                    } else {
                        group.append(final)
                    }
                }
                result.append(group)
                continue
            }

            let token = JamoTables.scalarString(scalar)
            if options.decomposeDoubleVowels, let split = JamoTables.doubleVowelDecomposition[token] {
                result.append([split.0, split.1])
                continue
            }

            if options.decomposeDoubleFinals, let split = JamoTables.doubleFinalDecomposition[token] {
                result.append([split.0, split.1])
                continue
            }

            if options.preserveNonHangul {
                result.append([token])
            }
        }

        return result
    }

    public static func assemble(_ fragments: [String]) -> String {
        AssembleEngine.assemble(fragments)
    }

    public static func combineCharacter(_ choseong: String, _ jungseong: String, _ jongseong: String = "") -> String {
        guard let lIndex = JamoTables.choseongIndexByJamo[choseong],
              let jungseongToken = canonicalJungseongToken(jungseong),
              let vIndex = JamoTables.jungseongIndexByJamo[jungseongToken] else {
            return choseong + jungseong + jongseong
        }

        let finalToken = canonicalJongseongToken(jongseong) ?? ""
        guard let tIndex = JamoTables.jongseongIndexByJamo[finalToken],
              let scalar = UnicodeHangul.compose(l: lIndex, v: vIndex, t: tIndex) else {
            return choseong + jungseong + jongseong
        }

        return String(scalar)
    }

    public static func combineCharacterStrict(_ choseong: String, _ jungseong: String, _ jongseong: String = "") throws -> String {
        guard let lIndex = JamoTables.choseongIndexByJamo[choseong],
              let jungseongToken = canonicalJungseongToken(jungseong),
              let vIndex = JamoTables.jungseongIndexByJamo[jungseongToken] else {
            throw HangulCoreError.invalidHangulComponents(choseong: choseong, jungseong: jungseong, jongseong: jongseong)
        }

        let finalToken = canonicalJongseongToken(jongseong) ?? ""
        guard let tIndex = JamoTables.jongseongIndexByJamo[finalToken],
              let scalar = UnicodeHangul.compose(l: lIndex, v: vIndex, t: tIndex) else {
            throw HangulCoreError.invalidHangulComponents(choseong: choseong, jungseong: jungseong, jongseong: jongseong)
        }

        return String(scalar)
    }

    public static func combineVowels(_ vowel1: String, _ vowel2: String) -> String {
        JamoTables.doubleVowelComposition[vowel1 + vowel2] ?? (vowel1 + vowel2)
    }

    public static func canBeChoseong(_ character: String) -> Bool {
        JamoTables.choseongIndexByJamo[character] != nil
    }

    public static func canBeJungseong(_ character: String) -> Bool {
        canonicalJungseongToken(character) != nil
    }

    public static func canBeJongseong(_ character: String) -> Bool {
        canonicalJongseongToken(character) != nil
    }

    public static func disassembleCompleteCharacter(_ character: String) -> HangulCharacterComponents? {
        guard character.count == 1, let scalar = character.unicodeScalars.first,
              let components = UnicodeHangul.decompose(scalar) else {
            return nil
        }

        return HangulCharacterComponents(
            choseong: JamoTables.choseong[components.l],
            jungseong: decomposedJungseong(JamoTables.jungseong[components.v]),
            jongseong: decomposedJongseong(JamoTables.jongseong[components.t])
        )
    }

    public static func getChoseong(_ str: String, options: ChoseongOptions = .default) -> String {
        var result = String()
        result.reserveCapacity(str.count)

        var previousWasWhitespace = false

        for scalar in str.unicodeScalars {
            if let components = UnicodeHangul.decompose(scalar) {
                result.append(JamoTables.choseong[components.l])
                previousWasWhitespace = false
                continue
            }

            if JamoTables.isCompatibilityConsonant(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasWhitespace = false
                continue
            }

            if scalar.properties.isWhitespace {
                switch options.whitespacePolicy {
                case .keep:
                    if options.preserveNonHangul {
                        result.unicodeScalars.append(scalar)
                        previousWasWhitespace = true
                    }
                case .normalize:
                    if options.preserveNonHangul, !result.isEmpty, !previousWasWhitespace {
                        result.append(" ")
                        previousWasWhitespace = true
                    }
                case .remove:
                    continue
                }
                continue
            }

            if options.preserveNonHangul {
                result.unicodeScalars.append(scalar)
                previousWasWhitespace = false
            }
        }

        return result
    }

    public static func getChoseongEsHangul(_ str: String) -> String {
        var result = String()
        result.reserveCapacity(str.count)

        for scalar in str.unicodeScalars {
            if let components = UnicodeHangul.decompose(scalar) {
                result.append(JamoTables.choseong[components.l])
                continue
            }

            if (0x1100...0x1112).contains(scalar.value) {
                let index = Int(scalar.value - 0x1100)
                result.append(JamoTables.choseong[index])
                continue
            }

            if JamoTables.isCompatibilityConsonant(scalar) {
                result.unicodeScalars.append(scalar)
                continue
            }

            if scalar.properties.isWhitespace {
                result.unicodeScalars.append(scalar)
            }
        }

        return result
    }

    public static func hasBatchim(_ word: String, options: BatchimOptions = .default) -> Bool {
        for scalar in word.unicodeScalars.reversed() {
            if scalar.properties.isWhitespace { continue }

            if options.strictCompleteSyllableOnly && UnicodeHangul.decompose(scalar) == nil {
                return false
            }

            if let components = UnicodeHangul.decompose(scalar) {
                guard components.t > 0 else { return false }
                let final = JamoTables.jongseong[components.t]
                let isDouble = JamoTables.doubleFinalDecomposition[final] != nil
                switch options.only {
                case .none:
                    return true
                case .single:
                    return !isDouble
                case .double:
                    return isDouble
                }
            }

            let token = JamoTables.scalarString(scalar)
            if let normalized = canonicalJongseongToken(token),
               let tIndex = JamoTables.jongseongIndexByJamo[normalized] {
                guard tIndex > 0 else { return false }
                let isDouble = JamoTables.doubleFinalDecomposition[normalized] != nil
                switch options.only {
                case .none:
                    return true
                case .single:
                    return !isDouble
                case .double:
                    return isDouble
                }
            }
            return false
        }

        return false
    }

    public static func removeLastCharacter(_ str: String) -> String {
        guard let last = str.last else { return str }
        let prefix = String(str.dropLast())

        guard let scalar = last.unicodeScalars.first,
              UnicodeHangul.isModernHangulSyllable(scalar),
              let components = UnicodeHangul.decompose(scalar) else {
            return prefix
        }

        if components.t > 0 {
            let final = JamoTables.jongseong[components.t]
            if let split = JamoTables.doubleFinalDecomposition[final],
               let keptT = JamoTables.jongseongIndexByJamo[split.0],
               let composed = UnicodeHangul.compose(l: components.l, v: components.v, t: keptT) {
                return prefix + String(composed)
            }
            if let composed = UnicodeHangul.compose(l: components.l, v: components.v, t: 0) {
                return prefix + String(composed)
            }
            return prefix
        }

        let vowel = JamoTables.jungseong[components.v]
        if let split = JamoTables.doubleVowelDecomposition[vowel],
           let keptV = JamoTables.jungseongIndexByJamo[split.0],
           let composed = UnicodeHangul.compose(l: components.l, v: keptV, t: 0) {
            return prefix + String(composed)
        }

        return prefix + JamoTables.choseong[components.l]
    }

    private static func canonicalJungseongToken(_ input: String) -> String? {
        if JamoTables.jungseongIndexByJamo[input] != nil { return input }
        if let composed = JamoTables.doubleVowelComposition[input] { return composed }
        return nil
    }

    private static func canonicalJongseongToken(_ input: String) -> String? {
        if JamoTables.jongseongIndexByJamo[input] != nil { return input }
        if let composed = JamoTables.doubleFinalComposition[input] { return composed }
        return nil
    }

    private static func decomposedJungseong(_ input: String) -> String {
        guard let split = JamoTables.doubleVowelDecomposition[input] else { return input }
        return split.0 + split.1
    }

    private static func decomposedJongseong(_ input: String) -> String {
        guard let split = JamoTables.doubleFinalDecomposition[input] else { return input }
        return split.0 + split.1
    }
}

public enum HangulCore {
    public static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
