# check-label

Fails the job unless the pull request carries one of the labels you require. Use it to gate merges on
a triage label, a semver label, or a release train label.

## Usage

```yaml
# .github/workflows/check-label.yml
name: check-label

on:
  pull_request:
    types: [opened, synchronize, labeled, unlabeled]

jobs:
  check-label:
    runs-on: ubuntu-latest

    permissions:
      pull-requests: read

    steps:
      - uses: coreruleset/actions/check-label@<sha> # pin@check-label-v<semantic-version>
        with:
          one_of: 'bug,enhancement,documentation'
```

Include `labeled` and `unlabeled` in `types` so the check re-runs when someone fixes the labels,
otherwise the pull request stays red until the next push.

## Inputs

| input          | required | default          | description                                                                |
| -------------- | -------- | ---------------- | -------------------------------------------------------------------------- |
| `one_of`       | yes      |                  | Comma separated list of labels; the pull request must carry at least one.   |
| `prefix_mode`  | no       | `false`          | Match a label that *starts with* one of the strings instead of exactly.     |
| `github_token` | no       | `${{ github.token }}` | Token used to read the labels. Needs `pull-requests: read`.            |

Whitespace around the commas is trimmed, so `one_of: 'bug, enhancement'` works. Labels containing
spaces (`good first issue`) are fine; labels containing commas are not, because the comma is the
separator.

### prefix_mode

```yaml
      - uses: coreruleset/actions/check-label@<sha> # pin@check-label-v<semantic-version>
        with:
          one_of: 'release/'
          prefix_mode: 'true'
```

Passes for `release/minor`, fails for `minor/release` and for a bare `release`.

## Development

The logic lives in [`match.sh`](match.sh) (label matching) and [`check.sh`](check.sh) (the `gh`
call around it), so both can be tested without a pull request — `check_test.sh` stubs `gh`:

```bash
./check-label/match_test.sh
./check-label/check_test.sh
```
