# Changelog

## Unreleased

### Fixed

- NFC/NFD 한글의 분해·초성·받침·조사·삭제 결과 일관성 보완.
- `preserveNonHangul: false`에서 기본 자모가 사라지는 문제 수정.
- 잘못된 받침을 조용히 버리지 않도록 엄격 조합 검증 수정.
- 완성형 조각 + 자모 및 독립 겹모음 조합 지원.
- 지수 표기 숫자의 한글 변환과 한 음절의 종성 발음 처리 수정.
- n-gram 검색의 짧은 공백 혼합 질의 누락, 유사 검색 후보 교집합 오류 수정.
- 후보 제한 전에 정확히 같은 원문을 우선 보존하도록 수정.
- 0 가중치 튜닝의 무한 반복, 변경 가능한 설정값의 범위·유한값 검증 보완.

### Added

- 선택적 OSA 편집거리. 기존 Levenshtein 기본값과 이전 JSON 옵션 디코딩 유지.
- 정답/무관 검색어 평가 API: Recall@K, Precision@K, MRR, 오추천 비율.
- 독립 검증셋 튜닝 및 검증 성능 하락 시 기존 가중치 유지.
- Nightly의 검색어 그룹 단위 학습/검증 분리. 서로 다른 검색어가 2개 미만이면 튜닝하지 않음.
- 안전한 Item의 검색 결과에 조건부 `Sendable` 적용.

### Changed

- 완성형 질의의 Jaccard·접두 보너스는 원문 기준으로 계산. 초성 전용 질의만 초성 기준 적용.
- 자모·키보드 비교에서 혼합 문자열의 비한글 문자를 보존.
- 검색어 특징 재사용, bounded Top-K 힙, 작은 쪽 문자열 길이만큼의 거리 계산 메모리 사용.
- 비동기 검색·설명 API에서 거리 계산 도중에도 취소 확인.
- 튜닝 후보 최대 1,024개, 피드백 학습 샘플 최대 50,000개로 작업량 방어.
- README에 동일 환경의 변경 전후 성능, 메모리, 합성 품질 평가와 한계 기록.

점수 구성과 후보 수집이 변경되어 기존 가중치·최소 점수는 자체 평가셋으로 재검증해야 합니다. 라이브러리는 아직 새 태그로 배포하지 않았습니다.

## 1.0.1 - 2026-03-25

### Changed

- CI/Actions
  - `actions/checkout` upgraded to `v5` for Node 24 migration readiness
  - `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` applied in workflows
  - secret scan step now falls back to `grep` when `rg` is unavailable on runner

- Build compatibility
  - `Package.swift` tools version lowered from `6.2` to `6.0`
  - README minimum Swift version updated to `6.0+`

- Test stability
  - search performance thresholds adjusted for CI host variance
  - retained relative performance guard (`ngram` p95 must stay faster than `precompute`)

## 1.0.0 - 2026-03-22

### Added

- `HangulCore`
  - disassemble / assemble
  - getChoseong
  - hasBatchim / josa
  - keyboard conversion helpers
  - number/pronunciation/romanization helpers

- `HangulSearch`
  - choseong-aware search index
  - index strategies: `precompute`, `lazyCache`, `ngram`
  - async search + cancellation
  - similarity scoring and tuning utilities

### Security / Stability

- Config file hardening
  - symbolic link access blocked
  - default POSIX permission guard (`dir 0700`, `file 0600`)
- `SimilarityConfigFileStore` actor 전환 (동시성 안전성 강화)

### Notes

- Package products: `HangulCore`, `HangulSearch`
- Sample app is located under `Examples/HangulSampleApp` and is not part of library targets.
