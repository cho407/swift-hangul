# Changelog

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
