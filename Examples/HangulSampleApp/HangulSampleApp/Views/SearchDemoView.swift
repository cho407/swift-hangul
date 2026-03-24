import SwiftUI
import HangulSearch

struct SearchDemoView: View {
    @StateObject private var viewModel = SearchDemoViewModel()
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    GroupBox("실시간 입력 (단일 입력)") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("검색어를 입력하면 실시간으로 검색됩니다.", text: $viewModel.query)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: viewModel.query) { _, _ in
                                    viewModel.onQueryChanged()
                                }

                            HStack {
                                if viewModel.isSearching {
                                    Label("검색 중", systemImage: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(viewModel.statusMessage)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("초기화") {
                                    viewModel.clearQuery()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }

                    GroupBox("설정 요약") {
                        VStack(alignment: .leading, spacing: 8) {
                            KeyValueRow(title: "현재 설정", value: viewModel.settingsSummary)

                            if let telemetry = viewModel.telemetry {
                                KeyValueRow(
                                    title: "Telemetry",
                                    value: "sync \(telemetry.syncSearchCount) / async \(telemetry.asyncSearchSuccessCount) / cacheHit \(telemetry.cacheHitCount)"
                                )
                                KeyValueRow(
                                    title: "평균 지연(ms)",
                                    value: String(
                                        format: "search %.2f | similar %.2f",
                                        telemetry.meanAsyncSearchLatencyMs,
                                        telemetry.meanAsyncSimilarLatencyMs
                                    )
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }

                    GroupBox("직접 매칭 결과 (\(viewModel.directResults.count))") {
                        VStack(alignment: .leading, spacing: 10) {
                            if viewModel.directResults.isEmpty {
                                Text("결과 없음")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.directResults) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.headline)
                                        Text(item.subtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(item.tags.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }

                    if viewModel.similarityChoice == .enabled {
                        GroupBox("유사도 결과 (\(viewModel.similarResults.count))") {
                            VStack(alignment: .leading, spacing: 10) {
                                if viewModel.similarResults.isEmpty {
                                    Text("유사도 결과 없음")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(viewModel.similarResults, id: \.item.id) { scored in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(scored.item.title)
                                                .font(.headline)
                                            Text("score \(String(format: "%.3f", scored.score))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("matched: \(scored.matchedQuery)")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                        }
                    }
                }
                .frame(maxWidth: 840, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("HangulSearch Demo")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Label("설정", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                SearchSettingsSheet(viewModel: viewModel)
            }
        }
    }
}

private struct SearchSettingsSheet: View {
    @ObservedObject var viewModel: SearchDemoViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("검색 기본") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("인덱스 전략")
                                Spacer(minLength: 16)
                                Picker("인덱스 전략", selection: $viewModel.selectedStrategy) {
                                    ForEach(SearchStrategyChoice.allCases) { strategy in
                                        Text(strategy.rawValue).tag(strategy)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 220)
                            }

                            Text(viewModel.selectedStrategy.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(alignment: .firstTextBaseline) {
                                Text("매치 모드")
                                Spacer(minLength: 16)
                                Picker("매치 모드", selection: $viewModel.selectedMode) {
                                    ForEach(MatchModeChoice.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 220)
                            }

                            HStack(alignment: .firstTextBaseline) {
                                Text("유사도 검색")
                                Spacer(minLength: 16)
                                Picker("유사도 검색", selection: $viewModel.similarityChoice) {
                                    ForEach(SimilarityChoice.allCases) { value in
                                        Text(value.rawValue).tag(value)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 220)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }

                    GroupBox("성능/랭킹 튜닝") {
                        VStack(alignment: .leading, spacing: 14) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 260), spacing: 16)],
                                spacing: 14
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Debounce")
                                        Spacer()
                                        Text("\(viewModel.debounceMilliseconds)ms")
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(
                                        value: Binding(
                                            get: { Double(viewModel.debounceMilliseconds) },
                                            set: { viewModel.debounceMilliseconds = Int($0.rounded()) }
                                        ),
                                        in: 0...700,
                                        step: 20
                                    )
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("유사도 최소 점수")
                                        Spacer()
                                        Text(String(format: "%.2f", viewModel.minimumSimilarityScore))
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: $viewModel.minimumSimilarityScore, in: 0.0...0.6, step: 0.01)
                                }
                            }

                            Stepper(
                                "최대 결과 수: \(viewModel.maxResults)",
                                value: $viewModel.maxResults,
                                in: 5...100,
                                step: 5
                            )

                            Toggle("한/영 자판 변환 후보 포함", isOn: $viewModel.includeLayoutVariants)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("검색 설정")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 760, minHeight: 620)
#endif
    }
}

#Preview {
    SearchDemoView()
}
