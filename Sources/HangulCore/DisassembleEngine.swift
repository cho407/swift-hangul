import Foundation

@usableFromInline
internal enum DisassembleEngine {
    static func disassemble(_ str: String, options: DisassembleOptions) -> String {
        var result = String()
        result.reserveCapacity(str.utf8.count)

        for scalar in str.precomposedStringWithCanonicalMapping.unicodeScalars {
            if let components = UnicodeHangul.decompose(scalar) {
                result.append(JamoTables.choseong[components.l])

                let vowel = JamoTables.jungseong[components.v]
                if options.decomposeDoubleVowels, let split = JamoTables.doubleVowelDecomposition[vowel] {
                    result.append(split.0)
                    result.append(split.1)
                } else {
                    result.append(vowel)
                }

                if components.t > 0 {
                    let final = JamoTables.jongseong[components.t]
                    if options.decomposeDoubleFinals, let split = JamoTables.doubleFinalDecomposition[final] {
                        result.append(split.0)
                        result.append(split.1)
                    } else {
                        result.append(final)
                    }
                }
                continue
            }

            let jamo = UnicodeHangul.compatibilityJamo(scalar)
            let asString = jamo ?? JamoTables.scalarString(scalar)
            if options.decomposeDoubleVowels, let split = JamoTables.doubleVowelDecomposition[asString] {
                result.append(split.0)
                result.append(split.1)
                continue
            }

            if options.decomposeDoubleFinals, let split = JamoTables.doubleFinalDecomposition[asString] {
                result.append(split.0)
                result.append(split.1)
                continue
            }

            if jamo != nil || options.preserveNonHangul {
                result.append(asString)
            }
        }

        return result
    }
}
