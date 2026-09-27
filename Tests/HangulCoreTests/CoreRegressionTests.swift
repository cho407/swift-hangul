import XCTest
@testable import HangulCore

final class CoreRegressionTests: XCTestCase {
    func testStandaloneJamoAreHangul() {
        for split in [true, false] {
            let options = DisassembleOptions(
                decomposeDoubleVowels: split, decomposeDoubleFinals: split,
                preserveNonHangul: false
            )
            let expected = split ? "ㄱㅏㅗㅏㄱㅅ" : "ㄱㅏㅘㄳ"
            XCTAssertEqual(Hangul.disassemble("ㄱㅏㅘㄳA", options: options), expected)
            XCTAssertEqual(Hangul.disassembleToGroups("ㄱㅏㅘㄳA", options: options).flatMap { $0 }.joined(), expected)
        }
    }

    func testCanonicalEquivalenceAcrossCoreAPIs() {
        for word in ["한글", "값", "프론트엔드", "과"] {
            let nfd = word.decomposedStringWithCanonicalMapping
            XCTAssertEqual(Hangul.disassemble(nfd), Hangul.disassemble(word))
            XCTAssertEqual(Hangul.disassembleToGroups(nfd), Hangul.disassembleToGroups(word))
            XCTAssertEqual(Hangul.getChoseong(nfd), Hangul.getChoseong(word))
            XCTAssertEqual(Hangul.getChoseongEsHangul(nfd), Hangul.getChoseongEsHangul(word))
            XCTAssertEqual(Hangul.hasBatchim(nfd), Hangul.hasBatchim(word))
            XCTAssertEqual(Hangul.pickJosa(nfd, .subject), Hangul.pickJosa(word, .subject))
            XCTAssertEqual(Hangul.removeLastCharacter(nfd), Hangul.removeLastCharacter(word))
        }
        XCTAssertEqual(Hangul.getChoseong("\u{1112}\u{1100}"), "ㅎㄱ")
        XCTAssertEqual(Hangul.disassembleCompleteCharacter("값".decomposedStringWithCanonicalMapping),
                       Hangul.disassembleCompleteCharacter("값"))
    }

    func testCompositionDoesNotSilentlyDiscardInvalidFinal() {
        XCTAssertThrowsError(try Hangul.combineCharacterStrict("ㄱ", "ㅏ", "A"))
        XCTAssertEqual(Hangul.combineCharacter("ㄱ", "ㅏ", "A"), "ㄱㅏA")
        XCTAssertEqual(try Hangul.combineCharacterStrict("ㄱ", "ㅏ"), "가")
    }

    func testAssemblyAcceptsSyllableFragmentsAndStandaloneVowels() {
        XCTAssertEqual(Hangul.assemble(["가", "ㄱ"]), "각")
        XCTAssertEqual(Hangul.assemble(["ㅗ", "ㅏ"]), "ㅘ")
        XCTAssertEqual(Hangul.assemble(["ㅗ", "ㅏ", "ㄱ", "ㅏ"]), "ㅘ가")
        XCTAssertEqual(Hangul.assemble(["갑", "ㅅ", "ㅣ"]), "갑시")
        XCTAssertEqual(Hangul.assemble(["\u{1100}", "\u{1161}", "\u{11A8}"]), "각")
        XCTAssertEqual(Hangul.convertQwertyToHangul("vm론트"), "프론트")
    }

    func testScientificNotationAndSingleSyllablePronunciation() {
        XCTAssertEqual(Hangul.numberToHangul(0.000001), "영점영영영영영일")
        XCTAssertEqual(Hangul.numberToHangul("1.25e3"), "천이백오십")
        XCTAssertEqual(Hangul.numberToHangul("1e999999999"), "영")
        XCTAssertEqual(Hangul.standardizePronunciation("값"), "갑")
        XCTAssertEqual(Hangul.standardizePronunciation("값".decomposedStringWithCanonicalMapping), "갑")
    }
}
