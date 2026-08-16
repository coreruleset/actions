# install-go-ftw

Downloads a [go-ftw](https://github.com/coreruleset/go-ftw) release and extracts the `ftw` binary.

Replaces the copy-pasted `gh release download ... | tar -xzvf - ftw` one-liner in
[coreruleset](https://github.com/coreruleset/coreruleset/blob/main/.github/workflows/test.yml) and
[modsecurity-crs-docker](https://github.com/coreruleset/modsecurity-crs-docker/blob/main/.github/workflows/verifyimage.yml),
with two fixes from
[modsecurity-crs-docker#464](https://github.com/coreruleset/modsecurity-crs-docker/pull/464):

- **The download is retried.** The release CDN resets connections now and then. The archive is
  written to a file and retried three times with a growing delay (5s, then 10s). Downloading to a
  file also means a truncated transfer fails at the download rather than inside `tar` — in the piped
  form the step exits with `tar`'s status, so a partial stream that `tar` happened to accept passed
  silently.
- **The architecture comes from the runner.** `uname -m` decides the asset, so it cannot drift apart
  from a `runs-on` mapping. go-ftw publishes `linux_amd64` and `linux_arm64` only; anything else
  fails with a message instead of downloading a binary that cannot exec.

## Usage

```yaml
      - uses: coreruleset/actions/install-go-ftw@<sha> # pin@install-go-ftw-v<semantic-version>
        with:
          version: '2.5.0'

      - run: ./ftw run -d tests/regression
```

Into a subdirectory, reading back the path:

```yaml
      - uses: coreruleset/actions/install-go-ftw@<sha> # pin@install-go-ftw-v<semantic-version>
        id: go-ftw
        with:
          version: '2.5.0'
          destination: crs

      - run: ${{ steps.go-ftw.outputs.path }} run -d tests/regression
```

## Inputs

| input          | required | default               | description                                                |
| -------------- | -------- | --------------------- | ---------------------------------------------------------- |
| `version`      | no       | `2.5.0`               | go-ftw release, with or without the leading `v`.            |
| `destination`  | no       | `.`                   | Directory to extract `ftw` into. Created if missing.        |
| `github_token` | no       | `${{ github.token }}` | Token used to download the release.                         |

## Outputs

| output | description                          |
| ------ | ------------------------------------ |
| `path` | Path to the extracted `ftw` binary.  |

## Development

The download lives in [`install.sh`](install.sh) so it can be tested without hitting the network —
[`install_test.sh`](install_test.sh) stubs `gh`, `uname` and `sleep` to cover the retry, give-up,
architecture and version-normalisation paths:

```bash
./install-go-ftw/install_test.sh
```
