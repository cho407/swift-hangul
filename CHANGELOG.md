# Changelog

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
