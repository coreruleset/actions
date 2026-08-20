# Changelog

## [4.0.0](https://github.com/coreruleset/actions/compare/crs-plugin-lint-v3.0.2...crs-plugin-lint-v4.0.0) (2026-08-16)


### ⚠ BREAKING CHANGES

* crs-plugin-test and crs-plugin-lint move here from coreruleset/crs-plugin-test-action. Callers must change the `uses:` path to coreruleset/actions/.github/workflows/crs-plugin-integration.yaml and coreruleset/actions/.github/workflows/crs-plugin-lint.yaml respectively.

### Features

* create the coreruleset actions monorepo ([0d0f60a](https://github.com/coreruleset/actions/commit/0d0f60a929aef10aaf11f82ae0c6d4824e5bd827))
