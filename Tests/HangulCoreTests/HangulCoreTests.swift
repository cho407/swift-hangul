import XCTest
@testable import HangulCore

final class HangulCoreTests: XCTestCase {
    private func benchmark(
        name: String,
        iterations: Int,
        block: () -> Void
    ) -> (meanMs: Double, stdMs: Double, minMs: Double, maxMs: Double) {
        var samples: [Double] = []
        samples.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            block()
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000.0)
        }

        let mean = samples.reduce(0, +) / Double(iterations)
        let variance = samples.reduce(0) { partial, value in
            let diff = value - mean
            return partial + (diff * diff)
        } / Double(iterations)
        let std = sqrt(variance)

        print("[BENCH][Core][\(name)] mean=\(String(format: "%.3f", mean))ms std=\(String(format: "%.3f", std))ms min=\(String(format: "%.3f", samples.min() ?? 0))ms max=\(String(format: "%.3f", samples.max() ?? 0))ms")

        return (mean, std, samples.min() ?? 0, samples.max() ?? 0)
    }

    func testDisassembleGoldenExamples() {
        XCTAssertEqual(Hangul.disassemble("값"), "ㄱㅏㅂㅅ")
        XCTAssertEqual(Hangul.disassemble("ㅘ"), "ㅗㅏ")
    }

    func testDisassemblePreserveOption() {
        let options = DisassembleOptions(
            decomposeDoubleVowels: true,
            decomposeDoubleFinals: true,
            preserveNonHangul: false
        )
        XCTAssertEqual(Hangul.disassemble("A값!", options: options), "ㄱㅏㅂㅅ")
    }

    func testGetChoseong() {
        XCTAssertEqual(Hangul.getChoseong("프론트엔드"), "ㅍㄹㅌㅇㄷ")
        XCTAssertEqual(Hangul.getChoseong("Swift 한글", options: .init(preserveNonHangul: true, whitespacePolicy: .remove)), "Swiftㅎㄱ")
        XCTAssertEqual(Hangul.getChoseongEsHangul("띄어 쓰기 ABC"), "ㄸㅇ ㅆㄱ ")
    }

    func testGetChoseongWhitespacePolicy() {
        let input = "가   나\t다\n라"
        XCTAssertEqual(
            Hangul.getChoseong(input, options: .init(preserveNonHangul: true, whitespacePolicy: .keep)),
            "ㄱ   ㄴ\tㄷ\nㄹ"
        )
        XCTAssertEqual(
            Hangul.getChoseong(input, options: .init(preserveNonHangul: true, whitespacePolicy: .normalize)),
            "ㄱ ㄴ ㄷ ㄹ"
        )
        XCTAssertEqual(
            Hangul.getChoseong(input, options: .init(preserveNonHangul: true, whitespacePolicy: .remove)),
            "ㄱㄴㄷㄹ"
        )
    }

    func testGetChoseongPreserveNonHangulFalse() {
        XCTAssertEqual(
            Hangul.getChoseong("Swift 한글 123!", options: .init(preserveNonHangul: false, whitespacePolicy: .keep)),
            "ㅎㄱ"
        )
    }

    func testGetChoseongWithCompatibilityConsonants() {
        XCTAssertEqual(Hangul.getChoseong("ㄱㄴabc값"), "ㄱㄴabcㄱ")
        XCTAssertEqual(
            Hangul.getChoseong("ㄱㄴabc값", options: .init(preserveNonHangul: false, whitespacePolicy: .remove)),
            "ㄱㄴㄱ"
        )
    }

    func testGetChoseongLargeInputSmoke() {
        let segment = "프론트엔드 Swift 검색 "
        let input = String(repeating: segment, count: 20_000)
        let result = Hangul.getChoseong(input, options: .init(preserveNonHangul: false, whitespacePolicy: .remove))
        XCTAssertEqual(result.count, 140_000)
    }

    func testHasBatchim() {
        XCTAssertTrue(Hangul.hasBatchim("값"))
        XCTAssertFalse(Hangul.hasBatchim("사과"))
    }

    func testAssembleMVP() {
        XCTAssertEqual(Hangul.assemble(["ㄱ", "ㅏ", "ㅂ", "ㅅ"]), "값")
        XCTAssertEqual(Hangul.assemble(["ㅍ", "ㅡ", "ㄹ", "ㅗ", "ㄴ", "ㅌ", "ㅡ"]), "프론트")
        XCTAssertEqual(
            Hangul.assemble(["아버지가", " ", "방ㅇ", "ㅔ ", "들ㅇ", "ㅓ갑니다"]),
            "아버지가 방에 들어갑니다"
        )
    }

    func testDisassembleToGroups() {
        XCTAssertEqual(Hangul.disassembleToGroups("값"), [["ㄱ", "ㅏ", "ㅂ", "ㅅ"]])
        XCTAssertEqual(Hangul.disassembleToGroups("ㅘ"), [["ㅗ", "ㅏ"]])
    }

    func testCombineHelpers() {
        XCTAssertEqual(Hangul.combineCharacter("ㄱ", "ㅏ", "ㅂㅅ"), "값")
        XCTAssertEqual(Hangul.combineVowels("ㅗ", "ㅏ"), "ㅘ")
    }

    func testCanBeJamo() {
        XCTAssertTrue(Hangul.canBeChoseong("ㄱ"))
        XCTAssertTrue(Hangul.canBeJungseong("ㅗㅏ"))
        XCTAssertTrue(Hangul.canBeJongseong("ㄱㅅ"))
        XCTAssertFalse(Hangul.canBeChoseong("A"))
    }

    func testDisassembleCompleteCharacter() {
        let components = Hangul.disassembleCompleteCharacter("값")
        XCTAssertEqual(components, .init(choseong: "ㄱ", jungseong: "ㅏ", jongseong: "ㅂㅅ"))
        XCTAssertNil(Hangul.disassembleCompleteCharacter("A"))
    }

    func testHasBatchimWithOptions() {
        XCTAssertTrue(Hangul.hasBatchim("값", options: .init(only: .double)))
        XCTAssertFalse(Hangul.hasBatchim("각", options: .init(only: .double)))
        XCTAssertTrue(Hangul.hasBatchim("각", options: .init(only: .single)))
    }

    func testRemoveLastCharacter() {
        XCTAssertEqual(Hangul.removeLastCharacter("값"), "갑")
        XCTAssertEqual(Hangul.removeLastCharacter("과"), "고")
        XCTAssertEqual(Hangul.removeLastCharacter("가"), "ㄱ")
        XCTAssertEqual(Hangul.removeLastCharacter("A"), "")
    }

    func testJosa() {
        XCTAssertEqual(Hangul.josa("사과", .object), "사과를")
        XCTAssertEqual(Hangul.josa("값", .subject), "값이")
        XCTAssertEqual(Hangul.pickJosa("길", .withInstrumental), "로")
        XCTAssertEqual(Hangul.pickJosa("학생", .status), "으로서")
        XCTAssertEqual(Hangul.pickJosa("라이벌", .status), "로서")
        XCTAssertEqual(Hangul.pickJosa("고기", .with), "랑")
        XCTAssertEqual(Hangul.pickJosa("과일", .with), "이랑")
        XCTAssertEqual(Hangul.pickJosa("집", "은/는"), "은")
        XCTAssertEqual(Hangul.pickJosa("", "이/가"), "이")
        XCTAssertEqual(Hangul.josa("", "이/가"), "")
    }

    func testJosaHeuristicsForNonHangul() {
        XCTAssertEqual(Hangul.pickJosa("3", .object), "을")
        XCTAssertEqual(Hangul.pickJosa("7", .withInstrumental), "로")
        XCTAssertEqual(Hangul.pickJosa("URL", .withInstrumental), "로")
        XCTAssertEqual(Hangul.pickJosa("API", .subject), "가")
        XCTAssertEqual(Hangul.pickJosa("album", .subject), "이")
        XCTAssertEqual(Hangul.pickJosa("값...", .subject), "이")
        XCTAssertEqual(Hangul.josa("URL", "을/를"), "URL을")
        XCTAssertEqual(Hangul.josa("CSS", "을/를"), "CSS를")
        XCTAssertEqual(Hangul.josa("URL", "으로/로"), "URL로")
    }

    func testKeyboardConversion() {
        XCTAssertEqual(Hangul.convertQwertyToAlphabet("ABC"), "ㅁㅠㅊ")
        XCTAssertEqual(Hangul.convertQwertyToAlphabet("RㅏㄱEㅜrl"), "ㄲㅏㄱㄸㅜㄱㅣ")
        XCTAssertEqual(Hangul.convertQwertyToHangul("ABC"), "뮻")
        XCTAssertEqual(Hangul.convertQwertyToHangul("vmfhsxm"), "프론트")
        XCTAssertEqual(Hangul.convertHangulToQwerty("프론트"), "vmfhsxm")
    }

    func testNumberAndAmountToHangul() {
        XCTAssertEqual(Hangul.numberToHangul(1234), "천이백삼십사")
        XCTAssertEqual(Hangul.numberToHangul("1203.45"), "천이백삼점사오")
        XCTAssertEqual(Hangul.numberToHangul(12_345, options: .init(spacing: true)), "일만 이천삼백사십오")
        XCTAssertEqual(Hangul.numberToHangulMixed(123456789), "1억2,345만6,789")
        XCTAssertEqual(Hangul.numberToHangulMixed(123456789, options: .init(spacing: true)), "1억 2,345만 6,789")
        XCTAssertEqual(Hangul.amountToHangul(1234), "천이백삼십사")
        XCTAssertEqual(Hangul.seosusa(1), "첫째")
        XCTAssertEqual(Hangul.seosusa(22), "스물두째")
        XCTAssertEqual(Hangul.seosusa(101), "백일째")
    }

    func testNumberToHangulEdgeCases() {
        XCTAssertEqual(Hangul.numberToHangul(1), "일")
        XCTAssertEqual(Hangul.numberToHangul("0001"), "일")
        XCTAssertEqual(Hangul.numberToHangul("0.05"), "영점영오")
        XCTAssertEqual(Hangul.numberToHangul("1,203.405"), "천이백삼점사영오")
        XCTAssertEqual(Hangul.numberToHangul("-0"), "영")
        XCTAssertEqual(Hangul.numberToHangul("abc"), "영")
        XCTAssertEqual(Hangul.numberToHangul(Double.infinity), "무한대")
        XCTAssertEqual(Hangul.numberToHangul(-Double.infinity, options: .init(spacing: true)), "마이너스 무한대")

        XCTAssertEqual(Hangul.numberToHangulMixed("001234567"), "123만4,567")
        XCTAssertEqual(Hangul.numberToHangulMixed("-0"), "0")
        XCTAssertEqual(Hangul.numberToHangulMixed("abc"), "영")
        XCTAssertEqual(Hangul.numberToHangulMixed(-Double.infinity), "-무한대")

        let hugeMixed = Hangul.numberToHangulMixed(String(repeating: "9", count: 80))
        XCTAssertFalse(hugeMixed.isEmpty)
    }

    func testSusaAndDays() {
        XCTAssertEqual(Hangul.susa(1), "하나")
        XCTAssertEqual(Hangul.susa(1, category: .modifier), "한")
        XCTAssertEqual(Hangul.susa(23), "스물셋")
        XCTAssertEqual(Hangul.susa(100), "백")
        XCTAssertEqual(Hangul.days(1), "하루")
        XCTAssertEqual(Hangul.days(10), "열흘")
        XCTAssertEqual(Hangul.days(11), "열하루")
        XCTAssertEqual(Hangul.days(20), "스무날")
        XCTAssertEqual(Hangul.days(21), "스무하루")
        XCTAssertEqual(Hangul.days(30), "서른날")
        XCTAssertEqual(Hangul.days(31), "31일")
    }

    func testPronunciationAndRomanize() {
        XCTAssertEqual(Hangul.standardizePronunciation("한글"), "한글")
        XCTAssertEqual(Hangul.romanize("한글"), "hangeul")
        XCTAssertEqual(Hangul.romanize("값"), "gap")
        XCTAssertEqual(Hangul.standardizePronunciation("국물"), "궁물")
        XCTAssertEqual(Hangul.standardizePronunciation("신라"), "실라")
        XCTAssertEqual(Hangul.standardizePronunciation("같이"), "가치")
        XCTAssertEqual(Hangul.standardizePronunciation("좋다"), "조타")
        XCTAssertEqual(Hangul.romanize("국물"), "gungmul")
        XCTAssertEqual(Hangul.romanize("신라"), "silla")
        XCTAssertEqual(Hangul.romanize("같이"), "gachi")
        XCTAssertEqual(Hangul.romanize("좋다"), "jota")
        XCTAssertEqual(Hangul.standardizePronunciation("깻잎"), "깬닙")
        XCTAssertEqual(Hangul.romanize("ㄱ"), "g")
        XCTAssertEqual(Hangul.romanize("ㅘ"), "wa")
    }

    func testPronunciationAndRomanizeOptions() {
        XCTAssertEqual(
            Hangul.standardizePronunciation("같이", options: .init(applyPalatalization: false)),
            "가티"
        )
        XCTAssertEqual(
            Hangul.standardizePronunciation("국물", options: .init(applyNasalization: false)),
            "국물"
        )

        XCTAssertEqual(
            Hangul.romanize("국물", options: .init(strategy: .literal, casing: .lowercase)),
            "gukmul"
        )
        XCTAssertEqual(
            Hangul.romanize("한글", options: .init(strategy: .pronunciation, casing: .uppercase)),
            "HANGEUL"
        )
    }

    func testPronunciationRuleCompatibilityExtended() {
        XCTAssertEqual(Hangul.standardizePronunciation("학여울"), "항녀울")
        XCTAssertEqual(Hangul.standardizePronunciation("맨입"), "맨닙")
        XCTAssertEqual(Hangul.standardizePronunciation("담요"), "담뇨")
        XCTAssertEqual(Hangul.standardizePronunciation("영업용"), "영엄뇽")
        XCTAssertEqual(Hangul.standardizePronunciation("콩엿"), "콩녇")
        XCTAssertEqual(Hangul.standardizePronunciation("알약"), "알략")
        XCTAssertEqual(Hangul.standardizePronunciation("서울역"), "서울력")
        XCTAssertEqual(Hangul.standardizePronunciation("불여우"), "불려우")
        XCTAssertEqual(Hangul.standardizePronunciation("고양이"), "고양이")
        XCTAssertEqual(Hangul.standardizePronunciation("윤여정"), "윤녀정")

        XCTAssertEqual(Hangul.standardizePronunciation("닦다", hardConversion: false), "닥다")
        XCTAssertEqual(Hangul.standardizePronunciation("앉다", hardConversion: false), "안다")
        XCTAssertEqual(Hangul.standardizePronunciation("맑다", hardConversion: false), "막다")
        XCTAssertEqual(Hangul.standardizePronunciation("곧이듣다", hardConversion: false), "고지듣다")

        XCTAssertEqual(Hangul.romanize("학여울"), "hangnyeoul")
        XCTAssertEqual(Hangul.romanize("알약"), "allyak")
        XCTAssertEqual(Hangul.romanize("호랑이"), "horangi")
    }

    func testRoundTripStabilityOnLargeCorpus() {
        let corpus = (0..<10_000).map { i in "프론트엔드 \(i) 한글 값 같이 국물 신라" }

        for text in corpus {
            let roundTrip = Hangul.assemble([Hangul.disassemble(text)])
            XCTAssertEqual(roundTrip, text)
        }
    }

    func testAllModernHangulSyllablesRoundTrip() {
        for value in 0xAC00...0xD7A3 {
            guard let scalar = UnicodeScalar(value) else {
                XCTFail("Invalid scalar: \(value)")
                return
            }

            let syllable = String(scalar)
            let disassembled = Hangul.disassemble(syllable)
            let reassembled = Hangul.assemble([disassembled])
            XCTAssertEqual(reassembled, syllable, "Round-trip mismatch at U+\(String(value, radix: 16).uppercased())")
        }
    }

    func testAllModernHangulSyllablesChoseongExtraction() {
        for value in 0xAC00...0xD7A3 {
            guard let scalar = UnicodeScalar(value) else {
                XCTFail("Invalid scalar: \(value)")
                return
            }

            let syllable = String(scalar)
            let choseong = Hangul.getChoseong(syllable, options: .init(preserveNonHangul: false, whitespacePolicy: .remove))
            XCTAssertEqual(choseong.count, 1, "Unexpected choseong length at U+\(String(value, radix: 16).uppercased())")
            XCTAssertTrue(Hangul.canBeChoseong(choseong), "Invalid choseong token at U+\(String(value, radix: 16).uppercased())")
        }
    }

    func testConcurrentDeterminismForGetChoseong() async {
        let input = String(repeating: "프론트엔드 Swift 검색 값 같이 국물 신라 ", count: 5_000)
        let baseline = Hangul.getChoseong(input, options: .init(preserveNonHangul: false, whitespacePolicy: .remove))

        await withTaskGroup(of: String.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    Hangul.getChoseong(input, options: .init(preserveNonHangul: false, whitespacePolicy: .remove))
                }
            }

            for await output in group {
                XCTAssertEqual(output, baseline)
            }
        }
    }

    func testCorePerformanceNumbers() {
        let input = String(repeating: "프론트엔드 Swift 검색 값 같이 국물 신라 ", count: 4_000)

        let choseongStats = benchmark(name: "getChoseong", iterations: 30) {
            _ = Hangul.getChoseong(input, options: .init(preserveNonHangul: false, whitespacePolicy: .remove))
        }

        let disassembleStats = benchmark(name: "disassemble", iterations: 20) {
            _ = Hangul.disassemble(input)
        }

        let assembledSeed = Hangul.disassemble(input)
        let assembleStats = benchmark(name: "assemble", iterations: 20) {
            _ = Hangul.assemble([assembledSeed])
        }

        // Loose but useful regression guardrails.
        XCTAssertLessThan(choseongStats.meanMs, 50)
        XCTAssertLessThan(disassembleStats.meanMs, 80)
        XCTAssertLessThan(assembleStats.meanMs, 120)
        XCTAssertLessThan(choseongStats.stdMs, 20)
    }

    func testCombineCharacterStrictAndBatchimStrict() throws {
        XCTAssertEqual(try Hangul.combineCharacterStrict("ㄱ", "ㅏ", "ㅂㅅ"), "값")
        XCTAssertThrowsError(try Hangul.combineCharacterStrict("가", "ㅏ", "ㄱ"))
        XCTAssertFalse(Hangul.hasBatchim("ㄱ", options: .init(only: nil, strictCompleteSyllableOnly: true)))
    }
}
