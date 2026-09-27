import Foundation

@usableFromInline
internal enum UnicodeHangul {
    static func compatibilityJamo(_ scalar: UnicodeScalar) -> String? {
        switch scalar.value {
        case 0x3131...0x3163: return String(scalar)
        case 0x1100...0x1112: return JamoTables.choseong[Int(scalar.value - 0x1100)]
        case 0x1161...0x1175: return JamoTables.jungseong[Int(scalar.value - 0x1161)]
        case 0x11A8...0x11C2: return JamoTables.jongseong[Int(scalar.value - 0x11A7)]
        case 0xFFA1...0xFFDC:
            let normalized = String(scalar).precomposedStringWithCompatibilityMapping
            guard let mapped = normalized.unicodeScalars.first, mapped != scalar else { return nil }
            return compatibilityJamo(mapped)
        default: return nil
        }
    }

    @usableFromInline static let sBase: UInt32 = 0xAC00
    @usableFromInline static let lCount: UInt32 = 19
    @usableFromInline static let vCount: UInt32 = 21
    @usableFromInline static let tCount: UInt32 = 28
    @usableFromInline static let nCount: UInt32 = vCount * tCount
    @usableFromInline static let sCount: UInt32 = lCount * nCount
    @usableFromInline static let sLast: UInt32 = sBase + sCount - 1

    @inlinable
    static func isModernHangulSyllable(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        return value >= sBase && value <= sLast
    }

    @inlinable
    static func decompose(_ scalar: UnicodeScalar) -> (l: Int, v: Int, t: Int)? {
        guard isModernHangulSyllable(scalar) else { return nil }
        let sIndex = scalar.value - sBase
        let l = Int(sIndex / nCount)
        let v = Int((sIndex % nCount) / tCount)
        let t = Int(sIndex % tCount)
        return (l, v, t)
    }

    @inlinable
    static func compose(l: Int, v: Int, t: Int) -> UnicodeScalar? {
        guard l >= 0, l < Int(lCount), v >= 0, v < Int(vCount), t >= 0, t < Int(tCount) else {
            return nil
        }
        let value = sBase + (UInt32(l) * nCount) + (UInt32(v) * tCount) + UInt32(t)
        return UnicodeScalar(value)
    }
}
