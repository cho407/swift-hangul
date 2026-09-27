import Foundation

@usableFromInline
internal enum AssembleEngine {
    private struct Composer {
        var currentL: Int?
        var currentV: Int?
        var currentT: Int?
        var result: String = ""

        init(capacity: Int) {
            result.reserveCapacity(capacity)
        }

        mutating func appendRaw(_ scalar: UnicodeScalar) {
            flushSyllableIfNeeded()
            result.unicodeScalars.append(scalar)
        }

        mutating func appendConsonant(_ jamo: String) {
            let lIndex = JamoTables.choseongIndexByJamo[jamo]
            let tIndex = JamoTables.jongseongIndexByJamo[jamo]

            if currentL == nil {
                flushSyllableIfNeeded()
                if let lIndex {
                    currentL = lIndex
                } else {
                    result.append(jamo)
                }
                return
            }

            if currentL != nil, currentV == nil {
                flushSyllableIfNeeded()
                if let lIndex {
                    currentL = lIndex
                } else {
                    result.append(jamo)
                }
                return
            }

            if currentL != nil, currentV != nil {
                guard let tIndex else {
                    flushSyllableIfNeeded()
                    if let lIndex {
                        currentL = lIndex
                    } else {
                        result.append(jamo)
                    }
                    return
                }

                if currentT == nil {
                    currentT = tIndex
                    return
                }

                let currentFinal = JamoTables.jongseong[currentT!]
                if let composedFinal = JamoTables.doubleFinalComposition[currentFinal + jamo],
                   let composedIndex = JamoTables.jongseongIndexByJamo[composedFinal] {
                    currentT = composedIndex
                } else {
                    flushSyllableIfNeeded()
                    if let lIndex {
                        currentL = lIndex
                    } else {
                        result.append(jamo)
                    }
                }
            }
        }

        mutating func appendVowel(_ jamo: String) {
            guard let vIndex = JamoTables.jungseongIndexByJamo[jamo] else {
                flushSyllableIfNeeded()
                result.append(jamo)
                return
            }

            if currentV == nil {
                currentV = vIndex
                return
            }

            if currentT == nil {
                let existingVowel = JamoTables.jungseong[currentV!]
                if let composed = JamoTables.doubleVowelComposition[existingVowel + jamo],
                   let composedIndex = JamoTables.jungseongIndexByJamo[composed] {
                    currentV = composedIndex
                } else {
                    flushSyllableIfNeeded()
                    currentV = vIndex
                }
                return
            }

            let finalJamo = JamoTables.jongseong[currentT!]
            if let split = JamoTables.doubleFinalDecomposition[finalJamo] {
                currentT = JamoTables.jongseongIndexByJamo[split.0]
                flushSyllableIfNeeded()
                if let lIndex = JamoTables.choseongIndexByJamo[split.1] {
                    currentL = lIndex
                    currentV = vIndex
                } else {
                    result.append(split.1)
                    result.append(jamo)
                }
                return
            }

            currentT = nil
            flushSyllableIfNeeded()
            if let lIndex = JamoTables.choseongIndexByJamo[finalJamo] {
                currentL = lIndex
                currentV = vIndex
            } else {
                result.append(finalJamo)
                result.append(jamo)
            }
        }

        mutating func flushSyllableIfNeeded() {
            guard let l = currentL else {
                if let v = currentV { result.append(JamoTables.jungseong[v]) }
                currentV = nil
                currentT = nil
                return
            }

            if let v = currentV,
               let scalar = UnicodeHangul.compose(l: l, v: v, t: currentT ?? 0) {
                result.unicodeScalars.append(scalar)
            } else {
                result.append(JamoTables.choseong[l])
            }

            currentL = nil
            currentV = nil
            currentT = nil
        }

        mutating func finalize() -> String {
            flushSyllableIfNeeded()
            return result
        }
    }

    static func assemble(_ fragments: [String]) -> String {
        var composer = Composer(capacity: fragments.reduce(0) { $0 + $1.utf8.count })

        func append(_ token: String) {
            // Tokens are validated modern jamo; avoid failed dictionary lookups for simple consonants.
            let value = token.unicodeScalars.first!.value
            if value >= 0x314F {
                if let split = JamoTables.doubleVowelDecomposition[token] {
                    composer.appendVowel(split.0)
                    composer.appendVowel(split.1)
                } else {
                    composer.appendVowel(token)
                }
            } else {
                switch value {
                case 0x3133, 0x3135...0x3136, 0x313A...0x3140, 0x3144:
                    let split = JamoTables.doubleFinalDecomposition[token]!
                    composer.appendConsonant(split.0)
                    composer.appendConsonant(split.1)
                default:
                    composer.appendConsonant(token)
                }
            }
        }

        for fragment in fragments {
            for scalar in fragment.unicodeScalars {
                if let parts = UnicodeHangul.decompose(scalar) {
                    append(JamoTables.choseong[parts.l])
                    append(JamoTables.jungseong[parts.v])
                    if parts.t > 0 { append(JamoTables.jongseong[parts.t]) }
                } else if let jamo = UnicodeHangul.compatibilityJamo(scalar) {
                    append(jamo)
                } else {
                    composer.appendRaw(scalar)
                }
            }
        }

        return composer.finalize()
    }
}
