import SwiftUI

struct CoreDemoView: View {
    @StateObject private var viewModel = CoreDemoViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    GroupBox("실시간 입력 (단일 입력)") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("예: 프론트엔드 / vmfhsxmdpsem / 319.04", text: $viewModel.inputText)
                                .textFieldStyle(.roundedBorder)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }

                    GroupBox("한글 핵심 처리") {
                        VStack(alignment: .leading, spacing: 8) {
                            valueLine("분해(disassemble)", viewModel.disassembled)
                            valueLine("재조합(assemble)", viewModel.reassembled)
                            valueLine("초성(getChoseong)", viewModel.choseong)
                            valueLine(
                                "받침(hasBatchim, 마지막 글자 기준)",
                                viewModel.hasBatchimOnLastSyllable ? "있음" : "없음"
                            )
                            valueLine(
                                "받침(단어 전체 중 하나라도)",
                                viewModel.hasBatchimAnywhere ? "있음" : "없음"
                            )
                            valueLine("판정 설명", viewModel.batchimExplanation)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }

                    GroupBox("키보드 변환") {
                        VStack(alignment: .leading, spacing: 8) {
                            valueLine("QWERTY → Hangul", viewModel.qwertyToHangul)
                            valueLine("Hangul → QWERTY", viewModel.hangulToQwerty)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }

                    GroupBox("조사 / 숫자 / 발음") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("조사", selection: $viewModel.selectedJosa) {
                                ForEach(CoreJosaChoice.allCases) { choice in
                                    Text(choice.rawValue).tag(choice)
                                }
                            }
                            .pickerStyle(.segmented)

                            valueLine("조사 적용", viewModel.josaApplied)
                            valueLine("numberToHangul", viewModel.numberHangul)
                            valueLine("numberToHangulMixed", viewModel.numberMixed)
                            valueLine("standardizePronunciation", viewModel.standardPronunciation)
                            valueLine("romanize", viewModel.romanized)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                }
                .frame(maxWidth: 840, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("HangulCore Demo")
        }
    }

    @ViewBuilder
    private func valueLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    CoreDemoView()
}
