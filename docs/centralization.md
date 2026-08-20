# Actions centralization

Where shared GitHub Actions work stands across the `coreruleset` org, and what is left to do.

Last updated 2026-08-20.

## Released from this repository

| action | version | replaces |
| --- | --- | --- |
| [`check-label`](../check-label/) | `check-label-v1.0.0` | new |
| [`crs-plugin-lint`](../crs-plugin-lint/) | `crs-plugin-lint-v4.0.0` | `crs-plugin-test-action` lint workflow |
| [`crs-plugin-test`](../crs-plugin-test/) | `crs-plugin-test-v4.0.0` | `crs-plugin-test-action` integration workflow |
| [`install-go-ftw`](../install-go-ftw/) | `install-go-ftw-v1.0.0` | six inline `gh release download` copies |

All four tags point at `83eb2c5f7d4ad87fffebdc8715271e6246b45937`.

## Survey findings

A pass over the org on 2026-08-16 covered all 64 active repositories — 137 workflow files across the
47 that have any. The four `coreruleset-ghsa-*` repositories and `coreruleset-private` were excluded:
they are security-advisory forks of `coreruleset`, so their duplication is a forking artefact and
inflates every count.

Two caveats on its reach. It was a point-in-time snapshot, and it only analysed `run:` blocks and
`uses:` lines under `.github/workflows/`. Duplication living in a repository's own `.github/scripts/`
or inside a composite action elsewhere would not have shown up.

### Addressed

**go-ftw installation** was the strongest finding: six copies of the same fragile one-liner across
five repositories — `coreruleset` (`test.yml` and `quantitative.yaml`), `modsecurity-crs-docker`,
`crs-plugin-test-action`, `status-page` and `rules-performance-tests`. Every copy hardcoded
`linux_amd64` and none retried. Now `install-go-ftw`.

### Still duplicated

| what | repositories | notes |
| --- | --- | --- |
| Container readiness check | `coreruleset`, `modsecurity-crs-docker` | `up -d` → `curl --retry` → `sleep 5` → `docker inspect .State.Running`. **Partly solved but not shareable**: it exists as `crs-plugin-test/wait-for-backend.sh`, reachable only through the plugin-test action. Extracting it as a standalone action would let both repositories drop their copy and replace the fixed `sleep 5` with a real readiness poll. |
| cosign signing of bake digests | `albedo`, `coraza-crs-docker`, `modsecurity-crs-docker` | The first two run an unquoted `images+="${tag}@${DIGEST} "` loop with no `set -euo pipefail`; `modsecurity-crs-docker` has already been hardened to a quoted bash array. Centralizing would propagate the fixed version. |
| Hugo + Dart Sass install | `documentation`, `website` | Byte-identical `wget` + `dpkg -i` of `hugo_extended`, plus `snap install dart-sass`. Only two repositories, but 100% identical and not pinned by digest. |
| `crs-linter` invocation | `coreruleset`, `crs-linter` | The same ten-flag command. Only one production consumer today, so worth it only if CRS-derived rulesets are expected to adopt it. |

### Ruled out

`setup-go` (7 repos), `setup-python` (9), CodeQL (5), and the docker `login` / `buildx` / `qemu`
trio are single third-party action calls whose configuration genuinely diverges — `go-version` vs
`go-version-file`, `cache: true` vs `false`. Wrapping them buys indirection rather than consistency.
The inconsistency there is a convention problem, not an action problem.

`check-label` has weak org-wide demand: only `coreruleset` gates on pull request metadata today, via
`amannn/action-semantic-pull-request`, and no repository checks labels the way this action does.

## Follow-up: migrate the plugin repositories

18 repositories consume `coreruleset/crs-plugin-test-action`, 36 references in total. That repository
**stays live** until the last one is migrated, so both can work in parallel.

Each repository changes one line per workflow:

```diff
 jobs:
   integration-tests:
-    uses: coreruleset/crs-plugin-test-action/.github/workflows/integration.yaml@<old>
+    uses: coreruleset/actions/.github/workflows/crs-plugin-integration.yaml@83eb2c5f7d4ad87fffebdc8715271e6246b45937 # pin@crs-plugin-test-v4.0.0
```

```diff
 jobs:
   plugin-lint:
-    uses: coreruleset/crs-plugin-test-action/.github/workflows/lint.yaml@<old>
+    uses: coreruleset/actions/.github/workflows/crs-plugin-lint.yaml@83eb2c5f7d4ad87fffebdc8715271e6246b45937 # pin@crs-plugin-lint-v4.0.0
```

Inputs are unchanged (`crs-config`, `backends`), with `go-ftw-version` added.

### Fix the pinning while you are there

9 of the 36 references use `@main` — unpinned, against the org's own policy — and the pinned ones are
spread across 7 distinct shas. That is a sign Renovate is not tracking reusable-workflow refs at all;
worth adding the right datasource to `coreruleset/renovate-config` so the new pins do not drift the
same way.

### Per-repository checklist

Current refs as of 2026-08-20; `main` means unpinned.

| repository | integration | lint | done |
| --- | --- | --- | --- |
| `body-decompress-plugin` | `580582e` | **main** | [ ] |
| `cpanel-rule-exclusions-plugin` | `738f25b` | `7e1ee6d` | [ ] |
| `dokuwiki-rule-exclusions-plugin` | `dc6ec81` | `7e1ee6d` | [ ] |
| `drupal-rule-exclusions-plugin` | `dc6ec81` | `7e1ee6d` | [ ] |
| `fake-bot-plugin` | `738f25b` | `ab51942` | [ ] |
| `false-positive-report-plugin` | **main** | **main** | [ ] |
| `ghost-rule-exclusions-plugin` | **main** | **main** | [ ] |
| `google-oauth2-plugin` | `738f25b` | `7e1ee6d` | [ ] |
| `machine-learning-integration-plugin` | `580582e` | **main** | [ ] |
| `nextcloud-rule-exclusions-plugin` | `81cb7f2` | `81cb7f2` | [ ] |
| `performance-plugin` | **main** | **main** | [ ] |
| `phpbb-rule-exclusions-plugin` | `738f25b` | `7e1ee6d` | [ ] |
| `phpmyadmin-rule-exclusions-plugin` | `738f25b` | `ab51942` | [ ] |
| `referer-hardening-plugin` | `dc6ec81` | `ab51942` | [ ] |
| `template-plugin` | `81cb7f2` | `7e1ee6d` | [ ] |
| `traffic-observation-plugin` | `580582e` | **main** | [ ] |
| `wordpress-rule-exclusions-plugin` | `81cb7f2` | `81cb7f2` | [ ] |
| `xenforo-rule-exclusions-plugin` | `738f25b` | `7e1ee6d` | [ ] |

Start with `template-plugin`: it is the starting point new plugins are copied from, so migrating it
first stops new repositories being created against the old path.

## Other open items

- `coreruleset/actions` has **no branch protection** on `main`. The "never push directly to main"
  rule is currently enforced only by a local `prek` hook.
- The org `.github` repository has no workflow templates — only a profile README — so every new
  repository still starts from copy-paste.
