# Actions

Reusable GitHub Actions for the [coreruleset](https://github.com/coreruleset) organisation. Each
action lives in its own top-level directory and is versioned independently.

| action | what it does |
| ------ | ------------ |
| [`check-label`](check-label/) | Fails the job unless the pull request carries one of the required labels |
| [`crs-plugin-lint`](crs-plugin-lint/) | Lints a CRS plugin's rule files and regression tests |
| [`crs-plugin-test`](crs-plugin-test/) | Runs a CRS plugin's go-ftw regression tests against ModSecurity |
| [`install-go-ftw`](install-go-ftw/) | Downloads the go-ftw binary for the runner's architecture, with retries |

Two reusable workflows wrap the plugin actions so plugin repositories keep a one line caller:
[`crs-plugin-integration.yaml`](.github/workflows/crs-plugin-integration.yaml) and
[`crs-plugin-lint.yaml`](.github/workflows/crs-plugin-lint.yaml). They exist because a matrix and a
second job cannot go in a composite action — see [Reusable workflows](#reusable-workflows) below.

Status of shared-actions work across the org, the survey behind it, and the plugin-repository
migration checklist: [`docs/centralization.md`](docs/centralization.md).

## Migrating from crs-plugin-test-action

`crs-plugin-test` and `crs-plugin-lint` are copies of
[coreruleset/crs-plugin-test-action](https://github.com/coreruleset/crs-plugin-test-action). **That
repository is still live.** The 18 plugin repositories move over one at a time, so both must keep
working until the last one is done.

Each plugin repository changes one line per workflow:

```diff
 jobs:
   integration-tests:
-    uses: coreruleset/crs-plugin-test-action/.github/workflows/integration.yaml@<old-sha>
+    uses: coreruleset/actions/.github/workflows/crs-plugin-integration.yaml@<sha>
```

```diff
 jobs:
   plugin-lint:
-    uses: coreruleset/crs-plugin-test-action/.github/workflows/lint.yaml@<old-sha>
+    uses: coreruleset/actions/.github/workflows/crs-plugin-lint.yaml@<sha>
```

Inputs are unchanged (`crs-config`, `backends`), with `go-ftw-version` added. While the migration is
open, keep behaviour equivalent to upstream — and see
[Replacing a third-party dependency](#replacing-a-third-party-dependency) for what "equivalent" has
to mean before dropping one of its dependencies.

## Usage

1. Follow the usage docs in the action's own `README.md`
1. Reference it as `coreruleset/actions/<action>@<sha>`, or for the plugin workflows as
   `coreruleset/actions/.github/workflows/<workflow>.yaml@<sha>`, and pin the sha with a comment
   naming the release tag, e.g. `# pin@check-label-v1.0.0`
1. Pin with [mheap/pin-github-action](https://github.com/mheap/pin-github-action)

    ```bash
    export GH_ADMIN_TOKEN=$(gh config get -h github.com oauth_token)
    pin-github-action .github/workflows/<workflow>.yml
    ```

## Contributing

### Setup

```bash
prek install          # or: pre-commit install
```

### Checks

The `lint` workflow runs these on every pull request; run them locally before pushing:

```bash
prek run --all-files
actionlint                                      # workflows only
zizmor .github/workflows ./*/action.yml         # workflows and composite actions
shellcheck ./*/*.sh run-tests.sh
./run-tests.sh                                  # every action's self-checks
```

`run-tests.sh` runs each `<action>/*_test.sh`. They put stubs for `gh`, `docker`, `curl`, `uname`,
`sleep` and `secrules-parser` on `PATH` and work in a `mktemp -d` tree, so they need no network, no
Docker and no pull request; a single suite runs on its own:

```bash
./install-go-ftw/install_test.sh
```

### New or updated actions

An action needs `action.yml` and a `README.md` documenting its inputs and a usage example.

Keep anything beyond glue in a `.sh` file next to `action.yml` and add a `*_test.sh` beside it —
`run-tests.sh` picks it up automatically. Inline `run:` blocks cannot be linted properly or tested
at all.

Pin every `uses:` to a full commit sha with a version comment, using
[ratchet](https://github.com/sethvargo/ratchet) or
[mheap/pin-github-action](https://github.com/mheap/pin-github-action). Renovate keeps them current.

### Replacing a third-party dependency

A third-party action that wraps a few lines of shell is a supply-chain liability for very little
benefit, especially one pinned to a sha on a branch rather than a release tag. Prefer a script here
with a test beside it — but only after demonstrating the replacement behaves the same:

1. Build the real thing at the ref currently pinned, and read its source for the defaults that apply
   (check what the consuming repositories actually configure — often nothing, so defaults are all
   that matter)
1. Run both over the edge shapes, and over violations injected into a clone of a real consumer
1. Keep those cases as the new `*_test.sh`, so the comparison does not have to be redone

[`crs-plugin-lint/check-eof.sh`](crs-plugin-lint/README.md#replacing-linelint) replaced
`fernandrone/linelint` this way. Reading its README was not enough: a file containing exactly `"\n"`
passes upstream, which neither the documentation nor a first reading of the rule made obvious.

While developing an action, prepend
[GitHubSecurityLab/actions-permissions/monitor](https://github.com/GitHubSecurityLab/actions-permissions/tree/main/monitor)
to it to discover the least privilege `permissions:` block it needs:

```yaml
      # Only necessary when first testing out an action
      - uses: GitHubSecurityLab/actions-permissions/monitor@e83639073897b68de235d81a783b2221cc13def7 # pin@v1
        with:
          config: ${{ vars.PERMISSIONS_CONFIG }}
```

The [Permissions Advisor](.github/workflows/github-permissions-advisor.yml) workflow reports the
same thing from a workflow's past runs.

## Releases

[release-please](https://github.com/googleapis/release-please) handles releases, one independent
version per action. On every push to `main` it opens or updates a single release PR; merging it cuts
a tag and a GitHub release for each action that changed, named
`{action-name}-v{major}.{minor}.{patch}`.

Config lives in [`.github/release-please-config.json`](.github/release-please-config.json), current
versions in [`.github/.release-please-manifest.json`](.github/.release-please-manifest.json).

### Commit messages decide the version

release-please reads [Conventional Commits](https://www.conventionalcommits.org/), so the message is
now load-bearing — an unrecognised prefix means **no release at all**, silently. Scope the commit
with the action's directory name so the right component is bumped:

```
feat(install-go-ftw): retry the release download        -> minor bump
fix(check-label): treat a failed gh call as a failure    -> patch bump
feat(crs-plugin-test)!: require an explicit backend      -> major bump
docs(check-label): ...                                   -> no release
```

A commit touching an action without a scope still releases it — the `paths` in the config decide
*which* component, the scope only makes it readable. Commits that touch no action directory (this
README, the lint workflow) never trigger a release.

To force a specific version, add a `Release-As: 1.0.0` footer to a commit. In manifest mode the
footer only applies to the components whose `paths` that commit touches.

### Starting versions

`crs-plugin-test` and `crs-plugin-lint` continue the series from
[crs-plugin-test-action](https://github.com/coreruleset/crs-plugin-test-action), which reached
`v3.0.2`, so the manifest seeds them at `3.0.2`. Moving a plugin repository to this repo is a
breaking change for the caller — the `uses:` path changes — so the first release here lands
`crs-plugin-test-v4.0.0`. A maintainer coming from `v3.0.2` sees a successor, not a rewrite that
apparently lost two major versions.

Nothing compares the two series mechanically: the tags live in different repositories and different
namespaces, and once a plugin repo swaps its `uses:` line, Renovate treats it as an entirely new
dependency. The version numbers exist for the humans doing the migration.

`check-label` and `install-go-ftw` are new, seeded at `0.0.0`, and debut at `1.0.0`: release-please
bumps the **major** for a breaking change below 1.0.0 unless `bump-minor-pre-major` is set, and it is
not set here. So a single `feat!:` commit releases `4.0.0` for the two inherited actions and `1.0.0`
for the two new ones, with no `Release-As` footer needed anywhere.

### What a tag actually points at

A tag names a commit of the **whole repository**, not just one directory. Pinning
`crs-plugin-test-v1.2.0` also gets you whatever `install-go-ftw/` looked like at that commit — which
matters, because `crs-plugin-test` calls `install-go-ftw/install.sh` directly. The version number
tells you what changed in that action; the sha tells you what you actually get.

### Adding an action to the release config

A new action must be added to both the config and the manifest, or it is merged but never released.
[`check-release-config.sh`](check-release-config.sh) fails the build when they drift apart — it also
catches a package with an empty `component`, which would silently tag `v1.2.0` instead of
`check-label-v1.2.0`.

```bash
./check-release-config_test.sh   # runs as part of ./run-tests.sh
```

### Dry run

Run the `release-please` workflow manually with **dry-run** ticked to preview what it would do
without creating a PR, tag, or release.

## Reusable workflows

Composite actions cannot express a `strategy.matrix` or a second job. Where an action needs one —
`crs-plugin-test` runs a matrix of backends × CRS refs, resolved after an LTS lookup job — a thin
reusable workflow in `.github/workflows/` owns the matrix and calls the action.

[Reusable workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows) must live
directly in `.github/workflows`, so these cannot sit in the action's own directory. Name them
`<action>-*.yaml` to keep the pairing obvious, and keep them thin: matrix, inputs, and nothing else.

A relative `uses: ./…` inside a reusable workflow resolves against the **caller's** repository, not
this one. To reach its own action, a wrapper checks this repository out at the ref the caller pinned:

```yaml
      - uses: actions/checkout@<sha> # pin@v7.0.1
        with:
          repository: ${{ job.workflow_repository }}
          ref: ${{ job.workflow_sha }}
          path: .crs-actions
          persist-credentials: false

      - uses: ./.crs-actions/crs-plugin-test
```

`job.workflow_sha` is the commit of the workflow file defining the job, so the action always matches
the ref the caller pinned — no second version to keep in step. actionlint's bundled context schema
does not know these two properties yet; the ignore in `.github/actionlint.yaml` is scoped to them.

## Notes

- [Custom actions](https://docs.github.com/en/actions/creating-actions/about-custom-actions) can
  live outside `.github/workflows`, which is why the actions themselves are composite.
- Composite actions cannot read the `secrets` context. Any token an action needs must be declared as
  an input and passed in by the calling workflow.
- [GitHub Actions Worm: Compromising GitHub Repositories Through the Actions Dependency Tree](https://www.paloaltonetworks.com/blog/prisma-cloud/github-actions-worm-dependencies/)
  — why everything is pinned to a sha.
