# swift-hangul

`swift-hangul`은 iOS/macOS용 한글 처리 및 검색 최적화 Swift 패키지입니다.

이 문서는 현재 `main` 기준입니다. 아직 태그로 배포하지 않은 변경은 [Unreleased](CHANGELOG.md#unreleased)에 정리합니다.

## 패키지 구성

- `HangulCore`
  - 한글 분해/조합
  - NFC/NFD 한글 및 현대 조합형 자모 처리
  - 초성 추출
  - 받침/조사 처리
  - 키보드(한/영) 변환
  - 숫자 한글화, 발음 표준화, 로마자 변환

- `HangulSearch`
  - `HangulCore` 기반 검색 인덱스
  - 초성/원문 검색 (`contains`, `prefix`, `exact`)
  - 전략: `precompute`, `lazyCache`, `ngram(k:2|3)`
  - 유사어 스코어링(편집거리, jaccard, 키보드 근접, 자모 유사도)
  - 선택적 OSA 거리(인접 글자 교환), 정답/무관 검색어 평가, 검증셋 분리 튜닝
  - async 검색 취소/텔레메트리

## Requirements

- Swift 6.0+
- iOS 15+
- macOS 14+

## Installation (SwiftPM)

```swift
dependencies: [
    .package(url: "https://github.com/hyunggu/swift-hangul.git", from: "1.0.0")
]
```

```swift
.product(name: "HangulCore", package: "swift-hangul")
.product(name: "HangulSearch", package: "swift-hangul")
```

## Quick Start

### HangulCore

```swift
import HangulCore

Hangul.disassemble("값")              // "ㄱㅏㅂㅅ"
Hangul.disassemble("ㅘ")              // "ㅗㅏ"
Hangul.assemble(["ㄱ","ㅏ","ㅂ","ㅅ"]) // "값"
Hangul.getChoseong("프론트엔드")       // "ㅍㄹㅌㅇㄷ"
Hangul.hasBatchim("값")                // true
```

### HangulSearch

```swift
import HangulSearch

struct Keyword: Sendable {
    let id: Int
    let name: String
}

let index = HangulSearchIndex(
    items: [
        Keyword(id: 1, name: "프론트엔드"),
        Keyword(id: 2, name: "백엔드"),
        Keyword(id: 3, name: "네이버"),
    ],
    keyPath: \.name,
    policy: .init(indexStrategy: .precompute, cache: .lru(capacity: 512))
)

let direct = index.search("프론트", mode: .contains)
let choseong = index.search("ㅍㄹㅌ", mode: .contains)
let similar = index.searchSimilar("vmfhsxmdpsem")
```

### 검색 동작

- 초성만 입력하면 초성으로, 완성형 단어를 입력하면 원문으로 직접 검색합니다. 원문 검색은 공백을 제외한 일치도 확인합니다. 초성의 공백 처리는 `choseongOptions.whitespacePolicy`를 따릅니다.
- `contains`는 부분 일치, `prefix`는 접두 일치, `exact`는 전체 키 또는 단어 단위 일치입니다.
- 유사 검색은 글자 형태를 비교합니다. 의미 기반 검색이나 문맥을 이해하는 교정기는 아닙니다.
- 기본 편집거리는 Levenshtein입니다. `SimilarityOptions(distanceAlgorithm: .optimalStringAlignment)`로 `apple`/`appel` 같은 인접 교환을 1회 편집으로 계산할 수 있습니다.
- 기본 `minimumScore`는 0.2입니다. 오추천 억제가 중요하면 0.45부터 자체 데이터로 평가하세요. 점수는 정답 확률이 아닙니다.
- n-gram 유사 검색은 일치 조각의 **합집합**으로 후보를 모으고, 짧은 검색어나 후보가 적을 때 스캔으로 보완합니다. 후보 제한을 사용하는 근사 검색이므로 모든 오타의 검색을 보장하지 않습니다.
- `maxCandidateScan`을 설정하면 직접 검색도 일부 데이터를 건너뛸 수 있습니다. 결과 누락이 허용되지 않으면 기본값 `nil`을 유지하세요.

`searchSimilar`와 `explainSimilar`는 같은 순위 계산을 사용하며, async API는 후보 처리와 거리 계산 중 취소를 확인합니다. `Item: Sendable`이면 검색 결과도 Task 사이에 전달할 수 있습니다.

튜닝은 `validationSamples`로 학습에 사용하지 않은 검색어를 검증할 수 있습니다. 정규화 후 같은 검색어는 학습셋에서 제외하며, 검증 점수가 하락하면 기존 가중치를 유지합니다. Nightly 파이프라인도 검색어 그룹 단위로 약 20%를 분리하며, 서로 다른 검색어가 최소 2개 필요합니다. 소규모 검증셋만으로 서비스 품질을 보장하지는 않습니다.

## 간단 성능 지표

측정: 2026-09-08, Apple M2, Swift 6.3.3, macOS 26.6.2, Release 최적화 빌드. 결과 캐시 없이 같은 검색을 20회 측정했습니다. p95는 20개 측정값 중 19번째 값입니다.

Core는 104,000자 혼합 문자열을 사용했습니다. 조합에는 해당 문자열의 완전 분해 결과를 입력했습니다.

| Core API | 평균 (ms) | 반복 |
| --- | ---: | ---: |
| `getChoseong` | 4.1 | 30 |
| `disassemble` | 22.2 | 20 |
| `assemble` | 26.8 | 20 |

32개 한글 키워드에 숫자를 붙인 합성 데이터입니다. 직접 검색은 `ㅍㄹㅌㅇㄷ`, 유사 검색은 `나이버`, 결과 20개·후보 1,200개·자판 변환 비활성 조건입니다. 실제 데이터 길이와 일치 비율에 따라 달라집니다.

| 데이터 | 전략 | 구축 (ms, 1회) | 직접 검색 p95 (ms) | 유사 검색 p95 (ms) | 프로세스 최대 RSS (MiB) |
| ---: | --- | ---: | ---: | ---: | ---: |
| 10,000 | precompute | 53.1 | 9.7 | 25.6 | 10.6 |
| 10,000 | lazyCache | 20.3 | 8.2 | 22.6 | 10.5 |
| 10,000 | ngram(2) | 130.7 | 0.3 | 10.1 | 13.0 |
| 60,000 | precompute | 226.8 | 51.2 | 75.1 | 25.6 |
| 60,000 | lazyCache | 127.5 | 52.0 | 81.4 | 25.6 |
| 60,000 | ngram(2) | 878.7 | 1.8 | 18.2 | 46.3 |
| 100,000 | precompute | 374.6 | 84.5 | 119.6 | 37.6 |
| 100,000 | lazyCache | 217.0 | 89.1 | 132.0 | 37.6 |
| 100,000 | ngram(2) | 1,473.7 | 2.9 | 23.8 | 67.9 |

표의 검색 지연은 워밍 후 값입니다. lazyCache 첫 직접 검색은 1만/6만/10만 건에서 각각 24.1/145.9/256.3ms였습니다. 측정한 비동기 취소 응답은 0.08~0.15ms였으며 최대 지연을 보장하는 값은 아닙니다. RSS는 데이터·인덱스·검색·런타임을 모두 포함한 프로세스 최고값이며 인덱스 크기만을 뜻하지 않습니다.

변경 전과 비교하면 10만 건 precompute 유사 검색 p95는 **312.1 → 119.6ms**, 최대 RSS는 **42.5 → 37.6MiB**였습니다. 정확도 보정에는 비용도 있습니다. precompute 구축은 336.4 → 374.6ms, n-gram 유사 검색 p95는 13.0 → 23.8ms였습니다. 이전 n-gram이 누락했던 `프론드엔드` 후보는 현재 검색됩니다. 모든 경로가 빨라진 것은 아닙니다.

### 품질 평가

32개 단어의 원문·NFD·띄어쓰기·초성·자판 변환·오타 192개와 무관 검색어 16개를 평가했습니다. 네 전략에서 동일한 결과였으며, **소규모 합성 평가 수치이지 실사용 정확도가 아닙니다.**

| 최소 점수 | Recall@5 | Precision@5 | MRR | 무관 검색어 오추천 비율 |
| ---: | ---: | ---: | ---: | ---: |
| 0.20 (기본) | 100% | 41.9% | 1.000 | 12.5% (2/16) |
| 0.45 | 100% | 83.5% | 1.000 | 0% (0/16) |

Recall은 정답을 반환한 비율, Precision은 반환한 키 중 정답 비율입니다. 무관 검색어 오추천 비율은 정답이 없는 입력에 하나라도 추천한 비율입니다. 후보를 많이 반환하는 설정은 정답을 찾더라도 불필요한 추천이 늘 수 있습니다.

## Packaging Note

- `Examples/HangulSampleApp`는 샘플 앱이며, SwiftPM 라이브러리 타겟에는 포함되지 않습니다.
- SwiftPM 제품은 `HangulCore`, `HangulSearch` 두 개만 노출됩니다.

## Credits

- 아이디어/기능 범주는 [`es-hangul`](https://github.com/toss/es-hangul)을 레퍼런스로 설계했습니다.
- 본 프로젝트는 Swift/iOS/macOS 환경에 맞춘 별도 구현입니다.

## License

이 프로젝트는 [MIT License](LICENSE)를 따릅니다.

참고: `es-hangul`의 라이선스/저작권은 원저작자 저장소 정책을 따릅니다.
