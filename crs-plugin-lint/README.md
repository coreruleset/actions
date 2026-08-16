# crs-plugin-lint

Lints a CRS plugin: `yamllint` over the regression tests, an end-of-file check over the whole
repository, then `secrules-parser` over the plugin's `.conf` rule files.

A copy of the lint half of
[coreruleset/crs-plugin-test-action](https://github.com/coreruleset/crs-plugin-test-action), kept
step for step so both can run in parallel during the migration — with one dependency dropped, see
[below](#replacing-linelint).

## Usage from a plugin repository

```yaml
# .github/workflows/lint.yml
name: Plugin lint

on: [push, pull_request]

permissions:
  contents: read

jobs:
  plugin-lint:
    uses: coreruleset/actions/.github/workflows/crs-plugin-lint.yaml@<sha> # pin@crs-plugin-lint-v<semantic-version>
```

### Migrating from crs-plugin-test-action

```diff
 jobs:
   plugin-lint:
-    uses: coreruleset/crs-plugin-test-action/.github/workflows/lint.yaml@<old-sha>
+    uses: coreruleset/actions/.github/workflows/crs-plugin-lint.yaml@<sha>
```

## Usage as an action

```yaml
    steps:
      - uses: actions/checkout@<sha> # pin@v4
        with:
          persist-credentials: false

      - uses: coreruleset/actions/crs-plugin-lint@<sha> # pin@crs-plugin-lint-v<semantic-version>
```

## Inputs

| input            | required | default            | description                                        |
| ---------------- | -------- | ------------------ | -------------------------------------------------- |
| `plugin-dir`     | no       | `plugins`          | Directory holding the plugin's `.conf` rule files.  |
| `test-dir`       | no       | `tests/regression` | Directory holding the go-ftw tests to yamllint.     |
| `python-version` | no       | `3.x`              | Python used to run `secrules-parser`.               |

## Replacing linelint

Upstream used [`fernandrone/linelint`](https://github.com/fernandrone/linelint) for the end-of-file
check, pinned to a sha on `master` rather than a release tag — an unreviewable moving target for a
rule that is a dozen lines of shell. [`check-eof.sh`](check-eof.sh) replaces it.

None of the 18 plugin repositories ships a `.linelint.yml`, so all of them ran linelint's defaults:
ignore `.git/`, skip non-UTF-8 files, and `single-new-line: true`. `check-eof.sh` implements exactly
that:

- an empty file passes
- the last byte must be a newline
- the byte before it must not be, so `a\n\n` fails and `a\n` passes
- a file that is exactly `\n` passes, as it does upstream — linelint's strict branch only applies to
  files longer than one byte

Equivalence was checked against the real binary built at the pinned sha, not against its source:
19 end-of-file shapes (including CRLF, blank-line-only and single-byte files) and 8 violations
injected into a clone of `template-plugin`. Both tools agreed on every case. The harness is
`equiv.sh` in the scratchpad of the session that made the change; [`check-eof_test.sh`](check-eof_test.sh)
keeps the same cases as a permanent regression test.

## Development

```bash
./crs-plugin-lint/check-eof_test.sh
./crs-plugin-lint/lint-rules_test.sh
```

`lint-rules.sh` collects the `.conf` files with `find` rather than passing `plugins/*.conf` straight
through: an unmatched glob reaches `secrules-parser` as that literal string and is reported as a
missing file, which reads as a parse error rather than as an empty plugin.
