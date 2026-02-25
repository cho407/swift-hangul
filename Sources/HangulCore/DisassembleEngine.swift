import Foundation

@usableFromInline
internal enum DisassembleEngine {
    static func disassemble(_ str: String, options: DisassembleOptions) -> String {
        var result = String()
        result.reserveCapacity(str.count * 3)

        for scalar in str.unicodeScalars {
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

            let asString = JamoTables.scalarString(scalar)
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

            if options.preserveNonHangul {
                result.unicodeScalars.append(scalar)
            }
        }

        return result
    }
}
