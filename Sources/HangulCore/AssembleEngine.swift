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

            if currentL == nil {
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
                    result.append(jamo)
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
            guard let l = currentL else { return }

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
        let merged = fragments.joined()
        var composer = Composer(capacity: merged.count)

        for scalar in merged.unicodeScalars {
            let token = JamoTables.scalarString(scalar)
            if JamoTables.choseongIndexByJamo[token] != nil || JamoTables.jongseongIndexByJamo[token] != nil {
                composer.appendConsonant(token)
                continue
            }

            if JamoTables.jungseongIndexByJamo[token] != nil {
                composer.appendVowel(token)
                continue
            }

            composer.appendRaw(scalar)
        }

        return composer.finalize()
    }
}
