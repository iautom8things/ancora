# Ancora

Ancora links specs to tagged ExUnit tests and the production functions those
tests call. It detects drift across git revisions without running the target
project's code or tests.

Ancora is a successor inspired by
[spec_led_ex](https://github.com/iautom8things/specled_ex) (Copyright (c)
Mike Hostetler, MIT licensed).

## Installation

Add Ancora to the development and test dependencies in `mix.exs`:

```elixir
{:ancora, "~> 1.0", only: [:dev, :test], runtime: false}
```

Then scaffold the spec workspace and inspect the next action:

```bash
mix deps.get
mix spec.init
mix spec.prime --base HEAD
```

Ancora requires Elixir 1.18 or later. The public parse API below will remain
stable within the 1.x series.

## Everyday use

After setting `default_base` to your remote branch in `.spec/config.yml`, run:

```bash
mix spec.next
mix spec.check
```

These commands include committed feature changes relative to the configured
branch's merge base. `--base HEAD` compares only the working tree with the
latest commit. Use it during setup or to inspect uncommitted changes.

For a workspace with another name, pass `--spec-dir contracts` to check,
validate, status, next, prime, or review. The directory contains `specs/`,
`decisions/`, and `config.yml`. Gate and review require it inside the project
so Git can supply its previous contents. Nested Mix projects use their own
source paths and exclude changes in sibling projects.

## Public API

Ancora's semver-stable public API has four functions:

- `Ancora.Parser.parse_file/2`
- `Ancora.DecisionParser.parse_file/2`
- [Ancora.check/2](https://hexdocs.pm/ancora/Ancora.html#check/2)
- [Ancora.validate/2](https://hexdocs.pm/ancora/Ancora.html#validate/2)

Every other module and function is internal. Mix tasks are the supported
command-line interface. Their `--root` option is an internal affordance for
tooling and tests and is outside the semver commitment.

## How checks work

Ancora reads source files and git objects. It loads bytecode from its own
dependencies to look up exported functions. This is toolchain introspection,
not project execution. Trusted dependencies may run their `@on_load` hooks
when the tool loads them.

Tagged tests define which production functions belong to a subject. When
those functions or calls change, edit the subject's requirements or scenarios
in the same diff. Mechanical rewrites such as `mix format --migrate` still
need an explicit acknowledgment when they change the derived call set.

`Spec-Ack:` trailers are temporary development acknowledgments. Ancora warns
when an applied trailer exists only below the branch tip because a squash merge
will discard it. Before merging, copy that severity into `.spec/config.yml`
under `severities:` or a subject override, add the reason for an override, and
commit the config change. Subject overrides are scoped to one subject and
one finding code, optionally narrowed to one requirement with `requirement:`.
The warning clears once config supplies the same severity. It remains when
config is more severe because removing the trailer would still change the gate
result.

### Primary and transitive drift

A subject may declare `surface:` as a nonempty list of exact repo-relative
source paths. `surface: []`, globs, absolute paths and traversal are rejected.
Observed drift, additions and removals outside the list produce informational
`derived/drift_transitive`, `derived/growth_transitive` and
`derived/shrink_transitive` findings. Omitting the field keeps primary checks.
When both sides declare ownership, either side can keep a change primary;
first introduction and later ownership edits appear in review as policy changes.
Surface never claims coverage or unchanged behavior.

## Deprecated 1.x grammar

`Ancora.Parser.parse_file/2` keeps returning its `"exceptions"` key and keeps
parsing `spec-exceptions` blocks throughout the 1.x series. Both are deprecated
and will be removed in Ancora 2.0.

## CI

CI must pass `--base` explicitly. The `default_base` setting is a
local-development convenience and must not decide a CI comparison.

Run the gate against the target branch after fetching its remote ref:

```yaml
spec:
  runs-on: ubuntu-latest
  steps:
    - {uses: actions/checkout@v4, with: {fetch-depth: 0}}
    - uses: erlef/setup-beam@v1
    - run: mix deps.get && mix spec.check --base origin/main
```

Ancora rejects a shallow `base..HEAD` range when a boundary inside it has a
parent commit absent locally. Use `fetch-depth: 0` in CI, or run
`git fetch --unshallow` before the gate.

With `--json`, read the last stdout line that parses as JSON. The verdict line
follows the JSON report and remains the final stdout line.

## Migration

See [docs/migration.md](docs/migration.md) for the adoption checklist and the
old-to-new finding code map.

## License

MIT. Copyright (c) 2026 Manuel Zubieta. See [LICENSE](LICENSE) and
[NOTICE](NOTICE).

Ancora attributes calls to each tagged test, its applicable setup and reachable
test helpers. Neighboring tests and unused helpers do not contribute bindings.
Inspect the reported callsite chain before editing a contract. An unresolved
call is an analysis limitation, not evidence that a contract was removed.
Do not add cosmetic requirements or split tests just to clear a finding.

For infrastructure without a statically observable test call, use an exact,
reasoned exception. The file remains excepted rather than covered:

```yaml
overrides:
  - file: lib/my_app_web/router.ex
    code: change/uncovered_file
    severity: info
    reason: Exercised through the Phoenix request pipeline.
```

File exceptions accept only `info`, require a reason, and cannot combine with
`subject:` or `requirement:`. Subject overrides prefer a matching `requirement:`
over the subject default; duplicate selectors are rejected regardless of order.
