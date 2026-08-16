# crs-plugin-test

Runs a CRS plugin's [go-ftw](https://github.com/coreruleset/go-ftw) regression tests against a real
ModSecurity + CRS container, for **one backend and one CRS ref**.

This is the composite half of what
[coreruleset/crs-plugin-test-action](https://github.com/coreruleset/crs-plugin-test-action) does.
The apache/nginx × CRS-ref matrix and the LTS lookup live in the reusable workflow
[`crs-plugin-integration.yaml`](../.github/workflows/crs-plugin-integration.yaml), because a
composite action cannot express a matrix or a second job.

**Most plugin repositories want the reusable workflow, not this action** — see
[Usage](#usage-from-a-plugin-repository) below. Use the action directly only when you are driving
the matrix yourself.

## Usage from a plugin repository

```yaml
# .github/workflows/integration.yml
name: Integration tests

on: [push, pull_request]

permissions:
  contents: read

jobs:
  integration-tests:
    uses: coreruleset/actions/.github/workflows/crs-plugin-integration.yaml@<sha> # pin@crs-plugin-test-v<semantic-version>
```

That runs `apache` and `nginx` against both `main` and the current CRS LTS release, and uploads the
error logs on failure.

### Migrating from crs-plugin-test-action

One line per workflow. Both repositories work in parallel, so the plugin repositories can be moved
one at a time:

```diff
 jobs:
   integration-tests:
-    uses: coreruleset/crs-plugin-test-action/.github/workflows/integration.yaml@<old-sha>
+    uses: coreruleset/actions/.github/workflows/crs-plugin-integration.yaml@<sha>
```

The inputs are unchanged (`crs-config`, `backends`), with `go-ftw-version` added.

## Usage as an action

```yaml
    steps:
      - uses: actions/checkout@<sha> # pin@v4
        with:
          persist-credentials: false

      - uses: coreruleset/actions/crs-plugin-test@<sha> # pin@crs-plugin-test-v<semantic-version>
        with:
          backend: ${{ matrix.backend }}
          crs-ref: ${{ matrix.crs-ref }}
```

The action does not check out the caller's repository; run it from a plugin repository that is
already checked out. One backend runs per job — both servers bind port 80.

## Inputs

| input            | required | default            | description                                                            |
| ---------------- | -------- | ------------------ | ---------------------------------------------------------------------- |
| `backend`        | no       | `apache`           | Web server to test against: `apache` or `nginx`.                        |
| `crs-ref`        | no       | `main`             | Ref of `coreruleset/coreruleset` to test against.                       |
| `crs-config`     | no       | `''`               | Extra directives appended to `crs-setup.conf` before the server starts. |
| `test-dir`       | no       | `tests/regression` | Directory holding the go-ftw tests.                                     |
| `go-ftw-version` | no       | `2.5.0`            | go-ftw release to run the tests with.                                   |
| `timeout`        | no       | `60`               | Seconds to wait for the backend to answer before failing.               |
| `github_token`   | no       | `${{ github.token }}` | Token used to download the go-ftw release.                           |

### crs-config

```yaml
        with:
          crs-config: |
            SecAction "id:900110,phase:1,pass,nolog,setvar:tx.inbound_anomaly_score_threshold=5"
```

Appended to the `crs-setup.conf.example` that is mounted into the container. (Upstream wrote this to
`/tmp/crs-additional-setup.conf`, which nothing mounted, so the input had no effect.)

## Expected repository layout

```
plugins/                     # mounted read-only into /opt/owasp-crs/plugins
tests/regression/*.yaml      # go-ftw tests
```

The container runs with `MODSEC_RULE_ENGINE=DetectionOnly`, `BLOCKING_PARANOIA=4` and
`CRS_ENABLE_TEST_MARKER=1`, so tests assert on the log rather than on the response status.

## Development

Three scripts carry the logic, each covered without Docker or the network:

```bash
./crs-plugin-test/prepare_test.sh           # workspace layout, backend validation, crs-config
./crs-plugin-test/wait-for-backend_test.sh  # readiness polling, crash and timeout paths
./crs-plugin-test/resolve-lts_test.sh       # the LTS release jq filter
```

`wait-for-backend.sh` replaces the fixed `sleep 5` that the CRS workflows have carried: it returns
as soon as the container answers, distinguishes a crashed container from a timeout, and dumps the
compose logs on failure.

go-ftw is installed by calling [`install-go-ftw`](../install-go-ftw/)'s script directly rather than
with `uses:` — a relative `uses:` inside a composite action resolves against the *caller's*
workspace, not this repository.

The images are pinned by digest in [`docker-compose.yml`](docker-compose.yml); Renovate bumps them.
Starting the container and running the tests end to end is only exercised by consuming repositories.
