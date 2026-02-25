import Foundation

public extension Hangul {
    static func convertQwertyToAlphabet(_ input: String) -> String {
        var result = String()
        result.reserveCapacity(input.count)

        for scalar in input.unicodeScalars {
            let key = String(scalar)
            result.append(qwertyToJamo[key] ?? key)
        }

        return result
    }

    static func convertQwertyToHangul(_ input: String) -> String {
        if input.isEmpty { return "" }

        let alphabets = convertQwertyToAlphabet(input)
        var fragments: [String] = []
        fragments.reserveCapacity(alphabets.count)
        for scalar in alphabets.unicodeScalars {
            fragments.append(String(scalar))
        }
        return assemble(fragments)
    }

    static func convertHangulToQwerty(_ input: String) -> String {
        let decomposed = disassemble(input, options: .init(
            decomposeDoubleVowels: false,
            decomposeDoubleFinals: false,
            preserveNonHangul: true
        ))

        var result = String()
        result.reserveCapacity(decomposed.count)

        for scalar in decomposed.unicodeScalars {
            let token = String(scalar)
            if let mapped = jamoToQwerty[token] {
                result.append(mapped)
            } else if let split = JamoTables.doubleVowelDecomposition[token] {
                result.append(jamoToQwerty[split.0] ?? split.0)
                result.append(jamoToQwerty[split.1] ?? split.1)
            } else if let split = JamoTables.doubleFinalDecomposition[token] {
                result.append(jamoToQwerty[split.0] ?? split.0)
                result.append(jamoToQwerty[split.1] ?? split.1)
            } else {
                result.append(token)
            }
        }

        return result
    }

    private static let qwertyToJamo: [String: String] = [
        "r": "ㄱ", "R": "ㄲ", "s": "ㄴ", "e": "ㄷ", "E": "ㄸ", "f": "ㄹ", "a": "ㅁ", "q": "ㅂ", "Q": "ㅃ",
        "t": "ㅅ", "T": "ㅆ", "d": "ㅇ", "w": "ㅈ", "W": "ㅉ", "c": "ㅊ", "z": "ㅋ", "x": "ㅌ", "v": "ㅍ", "g": "ㅎ",
        "k": "ㅏ", "o": "ㅐ", "i": "ㅑ", "O": "ㅒ", "j": "ㅓ", "p": "ㅔ", "u": "ㅕ", "P": "ㅖ",
        "h": "ㅗ", "y": "ㅛ", "n": "ㅜ", "b": "ㅠ", "m": "ㅡ", "l": "ㅣ",
        "A": "ㅁ", "S": "ㄴ", "D": "ㅇ", "F": "ㄹ", "G": "ㅎ",
        "H": "ㅗ", "J": "ㅓ", "K": "ㅏ", "L": "ㅣ",
        "Z": "ㅋ", "X": "ㅌ", "C": "ㅊ", "V": "ㅍ", "B": "ㅠ", "N": "ㅜ", "M": "ㅡ",
        "Y": "ㅛ", "U": "ㅕ", "I": "ㅑ"
    ]

    private static let jamoToQwerty: [String: String] = [
        "ㄱ": "r", "ㄲ": "R", "ㄴ": "s", "ㄷ": "e", "ㄸ": "E", "ㄹ": "f", "ㅁ": "a", "ㅂ": "q", "ㅃ": "Q",
        "ㅅ": "t", "ㅆ": "T", "ㅇ": "d", "ㅈ": "w", "ㅉ": "W", "ㅊ": "c", "ㅋ": "z", "ㅌ": "x", "ㅍ": "v", "ㅎ": "g",
        "ㅏ": "k", "ㅐ": "o", "ㅑ": "i", "ㅒ": "O", "ㅓ": "j", "ㅔ": "p", "ㅕ": "u", "ㅖ": "P",
        "ㅗ": "h", "ㅛ": "y", "ㅜ": "n", "ㅠ": "b", "ㅡ": "m", "ㅣ": "l"
    ]
}
