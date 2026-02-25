import Foundation

@usableFromInline
internal enum UnicodeHangul {
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
