import Foundation
import Combine
import HangulCore

enum CoreJosaChoice: String, CaseIterable, Identifiable {
    case subject = "이/가"
    case object = "을/를"
    case topic = "은/는"
    case withInstrumental = "으로/로"

    var id: String { rawValue }

    var pair: JosaPair {
        switch self {
        case .subject:
            return .subject
        case .object:
            return .object
        case .topic:
            return .topic
        case .withInstrumental:
            return .withInstrumental
        }
    }
}

@MainActor
final class CoreDemoViewModel: ObservableObject {
    @Published var inputText: String = "" {
        didSet { scheduleRefresh() }
    }
    @Published var selectedJosa: CoreJosaChoice = .topic {
        didSet { scheduleRefresh() }
    }

    @Published private(set) var disassembled = ""
    @Published private(set) var reassembled = ""
    @Published private(set) var choseong = ""
    @Published private(set) var hasBatchimOnLastSyllable = false
    @Published private(set) var hasBatchimAnywhere = false
    @Published private(set) var batchimExplanation = ""
    @Published private(set) var qwertyToHangul = ""
    @Published private(set) var hangulToQwerty = ""
    @Published private(set) var josaApplied = ""
    @Published private(set) var numberHangul = ""
    @Published private(set) var numberMixed = ""
    @Published private(set) var standardPronunciation = ""
    @Published private(set) var romanized = ""
    private var refreshWorkItem: DispatchWorkItem?

    init() {
        applyOutputs(inputText: inputText, selectedJosa: selectedJosa)
    }

    deinit {
        refreshWorkItem?.cancel()
    }

    private func scheduleRefresh() {
        let text = inputText
        let josa = selectedJosa

        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyOutputs(inputText: text, selectedJosa: josa)
        }
        refreshWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func applyOutputs(inputText: String, selectedJosa: CoreJosaChoice) {
        let disassembledValue = Hangul.disassemble(inputText)
        let choseongValue = Hangul.getChoseong(inputText)
        let hasBatchimOnLastSyllableValue = Hangul.hasBatchim(inputText)
        let hasBatchimAnywhereValue = Self.containsBatchimAnywhere(inputText)
        let batchimExplanationValue = Self.makeBatchimExplanation(
            inputText: inputText,
            hasBatchimOnLastSyllable: hasBatchimOnLastSyllableValue,
            hasBatchimAnywhere: hasBatchimAnywhereValue
        )
        let hangulToQwertyValue = Hangul.convertHangulToQwerty(inputText)
        let qwertyToHangulValue = Hangul.convertQwertyToHangul(inputText)
        let josaAppliedValue = inputText.isEmpty ? "-" : Hangul.josa(inputText, selectedJosa.pair)
        let numberHangulValue: String
        let numberMixedValue: String
        if Self.isNumericLike(inputText) {
            numberHangulValue = Hangul.numberToHangul(inputText)
            numberMixedValue = Hangul.numberToHangulMixed(inputText)
        } else {
            numberHangulValue = "숫자 형식 입력이 아니어서 계산하지 않음"
            numberMixedValue = "숫자 형식 입력이 아니어서 계산하지 않음"
        }
        let standardPronunciationValue = Hangul.standardizePronunciation(inputText, hardConversion: true)
        let romanizedValue = Hangul.romanize(inputText)

        let fragments = Hangul.disassembleToGroups(inputText).flatMap { $0 }
        let reassembledValue = Hangul.assemble(fragments)

        disassembled = disassembledValue
        reassembled = reassembledValue
        choseong = choseongValue
        hasBatchimOnLastSyllable = hasBatchimOnLastSyllableValue
        hasBatchimAnywhere = hasBatchimAnywhereValue
        batchimExplanation = batchimExplanationValue
        qwertyToHangul = qwertyToHangulValue
        hangulToQwerty = hangulToQwertyValue
        josaApplied = josaAppliedValue
        numberHangul = numberHangulValue
        numberMixed = numberMixedValue
        standardPronunciation = standardPronunciationValue
        romanized = romanizedValue
    }

    private static func containsBatchimAnywhere(_ text: String) -> Bool {
        for character in text {
            if let components = Hangul.disassembleCompleteCharacter(String(character)),
               !components.jongseong.isEmpty {
                return true
            }
        }
        return false
    }

    private static func isNumericLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var hasDigit = false
        for scalar in trimmed.unicodeScalars {
            if (48...57).contains(scalar.value) {
                hasDigit = true
                continue
            }

            switch scalar.value {
            case 43, 45, 46, 44, 95: // + - . , _
                continue
            default:
                if scalar.properties.isWhitespace {
                    continue
                }
                return false
            }
        }
        return hasDigit
    }

    private static func makeBatchimExplanation(
        inputText: String,
        hasBatchimOnLastSyllable: Bool,
        hasBatchimAnywhere: Bool
    ) -> String {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else {
            return "입력 텍스트가 비어 있습니다."
        }

        let lastToken = String(last)
        if hasBatchimOnLastSyllable {
            return "마지막 글자 \"\(lastToken)\" 기준으로 받침이 있습니다."
        }

        if hasBatchimAnywhere {
            return "마지막 글자 \"\(lastToken)\"에는 받침이 없지만, 단어 내부에는 받침이 있는 음절이 있습니다."
        }

        return "마지막 글자 \"\(lastToken)\" 기준/단어 전체 기준 모두 받침이 없습니다."
    }
}
