# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` imports this file, so Claude Code
reads it too — keep the guidance here rather than splitting it per tool.

## What this is

A monorepo of reusable **composite GitHub Actions** for the `coreruleset` org, one per top-level
directory (`check-label/`, `crs-plugin-lint/`, `crs-plugin-test/`, `install-go-ftw/`). Each is
versioned and released independently as a tag `{dir-name}-v{major.minor.patch}`, by release-please.

`crs-plugin-test` and `crs-plugin-lint` are copies of
[`coreruleset/crs-plugin-test-action`](https://github.com/coreruleset/crs-plugin-test-action), which
is **still live**: 18 plugin repositories are being migrated one at a time, so both must keep
working. Keep behaviour equivalent to upstream while that is true.

"Equivalent" means *verified* equivalent, not *identical*. `crs-plugin-lint/check-eof.sh` replaces
upstream's `fernandrone/linelint` (pinned to a `master` sha) after both were run against the same
inputs and agreed on every case. That is the bar for dropping any other upstream dependency: build
the real thing at the pinned ref, run both over the shapes that matter and over violations injected
into a real plugin clone, then keep those cases as a permanent `*_test.sh`.

There is no build step and no package manager. The "code" is YAML plus a little bash. Consumers
reference an action as `coreruleset/actions/<action>@<sha>`.

Note: the git repo currently has **no commits and no remote**.

## Commands

```bash
prek run --all-files                        # hooks in .pre-commit-config.yaml (prefer over pre-commit)
actionlint                                  # workflows only; ignores composite action.yml files
zizmor .github/workflows ./*/action.yml     # security audit, covers composite actions too
shellcheck ./*/*.sh run-tests.sh
./run-tests.sh                              # every <action>/*_test.sh
```

The `lint` workflow runs all of these. `zizmor` must stay clean at the default (`regular`) persona;
`--persona=pedantic` findings are style nits and are not enforced.

## Testing

Every action keeps its real work in a `.sh` file next to `action.yml`, with a `*_test.sh` beside it
that `run-tests.sh` discovers by glob. Tests are plain bash with an `assert`/`fail` counter — no
framework — and must run offline, without Docker and without a pull request. They get there by
putting stubs on `PATH` (`gh`, `uname`, `sleep`) and running against a `mktemp -d` workspace; copy
the stub pattern from `install-go-ftw/install_test.sh`.

A stub has to fail the way the real thing fails, or the test passes for the wrong reason. Both of
these were found by mutation testing and only then written correctly: the `gh` stub in
`check_test.sh` prints labels *and then* exits non-zero (a check that only exits non-zero cannot
detect a missing `pipefail`, since empty output already fails the match), and the one in
`install_test.sh` leaves a truncated archive behind (otherwise the give-up cleanup is untested).

After changing a script, verify the tests still bite by mutating it — flip a condition, drop a
guard, swap two arguments — and confirm the suite goes red. Check the mutation actually applied;
a `sed` that silently matched nothing looks exactly like a test that caught the bug.

## Composite action constraints

These are not workflows, and the differences cause most of the bugs here:

- **No `secrets` context.** A composite action reading `${{ secrets.GITHUB_TOKEN }}` gets an empty
  string. Declare a `github_token` input instead, defaulting to `${{ github.token }}` — that
  expression *is* valid in an input default.
- **Each `run:` block is a script, not a function.** `return 0` does not signal success; use
  `exit 0` / `exit 1`. Start every block with `set -euo pipefail` — composite steps do not fail on
  a non-zero exit inside a multi-line script otherwise.
- **`shell:` is required on every `run:` step.**
- **No `matrix`, no second job.** An action takes `backend`/`crs-ref` style inputs and something else
  fans them out. Where that fan-out belongs to the org rather than the caller, a thin reusable
  workflow in `.github/workflows/<action>-*.yaml` owns it — see below.
- Files shipped alongside the action are reached via `$GITHUB_ACTION_PATH`, not a relative path —
  the working directory is the caller's workspace.
- **A relative `uses: ./other-action` resolves against the caller's workspace**, so it does not work
  for a sibling action here. `crs-plugin-test` reuses `install-go-ftw` by calling
  `"$GITHUB_ACTION_PATH/../install-go-ftw/install.sh"` — the whole repo is checked out together, and
  this avoids pinning a sibling to a released sha it does not have yet.

## Commits and releases

release-please derives every version from commit messages, so **commits must be Conventional
Commits** — `feat(install-go-ftw): …`, `fix(check-label): …`, `!` or a `BREAKING CHANGE:` footer for
a major. A message it does not recognise produces no release and no error; that silence is the
failure mode to watch for. Scope with the action's directory name.

Versions in `.release-please-manifest.json` are seeded by hand where an action inherits a series from
another repository — `crs-plugin-test` and `crs-plugin-lint` start at `3.0.2` because
`crs-plugin-test-action` reached `v3.0.2`, so their first release here is `4.0.0`. Write them as bare
semver; a leading `v` is read literally and produces a nonsense next version.

Note that release-please bumps the **major** for a breaking change below `1.0.0` — `bump-minor-pre-major`
is off — so an action seeded at `0.0.0` debuts at `1.0.0` from a `feat!:` commit, not `0.1.0`.

A new action needs an entry in `.github/release-please-config.json` *and*
`.github/.release-please-manifest.json`, or it can never be released.
`check-release-config.sh` (run by `run-tests.sh`) fails when they drift from the directories on
disk, and when a package has an empty `component` — which would tag `v1.2.0` instead of
`check-label-v1.2.0`.

An action whose behaviour also depends on a wrapper workflow lists both in its `paths`, so editing
the wrapper releases the action. `crs-plugin-test` does this with
`.github/workflows/crs-plugin-integration.yaml`.

## Reusable workflow wrappers

`.github/workflows/crs-plugin-*.yaml` are `workflow_call` workflows that exist only to own a matrix.
Two rules keep them from rotting:

- They must live directly in `.github/workflows` — subdirectories are not supported — so they cannot
  sit next to the action they wrap. The `<action>-*` filename is the only thing pairing them.
- A relative `uses: ./…` inside them resolves against the **caller's** repository. They reach their
  own action by checking this repo out at `${{ job.workflow_sha }}` (with
  `${{ job.workflow_repository }}`) into `.crs-actions/` first, so the action always matches the ref
  the caller pinned. Do not replace this with a hardcoded sha — that reintroduces a second version to
  keep in step. actionlint does not know these two `job` properties yet; `.github/actionlint.yaml`
  ignores exactly that message for these files.

Keep wrappers thin. Anything with logic belongs in the action, where the tests are.
- `actionlint` does not validate `action.yml`. A syntax error there only shows up as a zizmor
  "failed to parse input" warning or at runtime, so read that warning rather than skipping it.

## Conventions

**Pin every `uses:` and container image to a full sha** with a trailing `# pin@v<version>` comment.
This is the repo's main security property — see the Actions-worm link in `README.md`. Renovate
(`renovate.json`, extending `coreruleset/renovate-config`) keeps them current; there is deliberately
no Dependabot config. Pin new references with:

```bash
export GH_ADMIN_TOKEN=$(gh config get -h github.com oauth_token)
pin-github-action .github/workflows/<file>
```

Tag a bare version default that Renovate should track with a `# renovate: datasource=... depName=...`
comment above it (see `go-ftw-version` in `test-plugin/action.yml`).

**Non-trivial bash belongs in its own `.sh` file** next to the action, so shellcheck and a self-check
can reach it — `check-label/match.sh` plus `check-label/match_test.sh` is the pattern to copy. Inline
`run:` blocks are for glue only.

**A new action needs** `action.yml`, a `README.md` with an inputs table and a usage example, and a
lint or test job if it has logic worth checking. While developing one, prepend
`GitHubSecurityLab/actions-permissions/monitor` to discover its least-privilege `permissions:` block.

## crs-plugin-test specifics

`crs-plugin-test/docker-compose.yml` is vendored from `coreruleset/crs-plugin-test-action` rather
than curled at runtime, so its image digests are pinned and reviewable. Its bind-mount paths are
relative to the compose file, and the action copies it to `<workspace>/tests/integration/` at run
time — that location is what makes `../../crs/rules`, `../../plugins` and `../logs/<backend>`
resolve. Moving the copy changes every mount.

Two upstream bugs are fixed here and must not be "restored" for equivalence: apache mounted
`../../crs-setup.conf.example` (no such path, so docker created a directory), and `crs-config` was
written to `/tmp/crs-additional-setup.conf`, which nothing mounted — it is now appended to the
mounted `crs-setup.conf.example`.
