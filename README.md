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

## CI

CI must pass `--base` explicitly. The `default_base` setting is a
local-development convenience and must not decide a CI comparison.

Run the gate against the target branch after fetching its remote ref:

```yaml
spec:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: erlef/setup-beam@v1
    - run: mix deps.get && mix spec.check --base origin/main
```

With `--json`, read the last stdout line that parses as JSON. The verdict line
follows the JSON report and remains the final stdout line.

## Migration

See [docs/migration.md](docs/migration.md) for the adoption checklist and the
old-to-new finding code map.

## License

MIT. Copyright (c) 2026 Manuel Zubieta. See [LICENSE](LICENSE) and
[NOTICE](NOTICE).
