# Changelog

All notable changes to this project are documented in this file.

## 1.2.0 - 2026-09-05

Field friction: the fixes decided after one day of running 1.0 against a real
consumer (Atlas, six sessions), where CI came out green only with human
rulings, worker bounces, hand-ported gates, and retried flakes. Four behavior
changes a 1.1 repository meets on upgrade, each with its remedy in
`docs/migration.md`:

- Acknowledged findings are no longer suppressed. A drift, growth, or shrink
  finding cleared by a substantive spec edit stays in `all_findings` and in the
  JSON report at `info` with `severity_source: :ack`, and the branch summary
  line counts what each source hid: `hidden: default=N trailer=N ack=N config=N`.
- `derived/drift` splits in two once a subject declares a `surface:` list in
  its spec-meta: a changed function whose defining file is on the surface stays
  `derived/drift`; every other binding becomes `derived/drift_transitive` at
  `info`. Subjects without `surface:` behave as before.
- `change/missing_decision` clears when the edited spec names a governing,
  accepted ADR in its `decisions:` frontmatter and that ADR names the subject
  back in `affects:`. The path-only rule stays as the fallback.
- Two new disclosures default to `info` and are hidden in default output: a
  tag that binds a new test to an unchanged requirement (`tags/tag_borrowed`),
  and a requirement statement whose text moved (`append/statement_changed`).
  `--verbose` or `--explain-acks` shows them; the `next=` line now says how
  many findings are hidden and which flag reveals them. The registry grows
  from 30 to 33 codes.

### Added

- **Requirement-scoped overrides.** An `overrides:` entry may carry
  `requirement:` to narrow a subject-and-code override to one requirement;
  unknown requirement ids fail at load with `config/unknown_key`. The JSON
  report carries the optional `requirement` field. [ancora-gg8.1](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gg8.1.json)
- **Governed `change/missing_decision`.** A spec edit under an accepted ADR
  linked from `decisions:` no longer needs the ADR in the same diff. [ancora-gg8.2](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gg8.2.json)
- **`Ancora.SourceScan`** is the blessed no-execution source scanner for
  consumers, with the pattern documented in `docs/migration.md` and the
  scaffolded agent guide. [ancora-gg8.3](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gg8.3.json)
- **Primary versus transitive drift, visible acknowledgments, `--explain-acks`.**
  `surface:` scopes drift, acknowledged findings stay visible at `info` with
  their source, the review artifact shows an acknowledged badge and a distinct
  transitive-drift badge, and `--explain-acks` lists only the findings a
  trailer, config entry, or acknowledgment demoted. [ancora-gg8.5](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gg8.5.json)
- **`tags/tag_borrowed` and `append/statement_changed`** disclose borrowed
  tags and moved statements at `info`; a tag on an edited or new requirement,
  and whitespace-only or priority-only edits, stay silent. [ancora-gg8.6](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gg8.6.json)

### Fixed

- **A trailing slash in `lib_paths` made `change/uncovered_file` unclearable.**
  Paths are normalized once at config load, and change analysis honors the
  configured `lib_paths` instead of a hardcoded `lib/`. [ancora-ufm](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-ufm.json)
- **Pre-PR review fixes.** Four messages printed the requirement id twice
  (`ancora.derive.ancora.derive.x`); the review page had no card for
  transitive drift and colored it as acknowledged; the hidden-count rollup had
  no bucket for `config.yml` demotions; a proposed or superseded ADR cleared
  `change/missing_decision`; a worker crash inside the parallel parse loops
  killed `mix spec.check` with a raw EXIT and no verdict line (now an
  environment-tier verdict); `tags/tag_borrowed` carried no subject, so no
  override could reach it; the definition-index workers copied the whole
  per-side AST map into every task. [ancora-gg8.9](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gg8.9.json)

### Changed

- **One derivation per command.** `spec.prime`, `spec.status`, and decision
  validation each derived the corpus two or three times; they now derive once
  and share the result. Output is byte-identical. [ancora-gg8.4](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gg8.4.json)
- **Parallel parsing, one parse per file and side.** The four sequential
  parse loops (module locator, tag scanner, definition indexes, spec index) run
  as ordered `Task.async_stream` pipelines, and the module locator hands its
  ASTs to the definition-index build so lib files parse once per side. Finding
  order is identical run to run, pinned by a ten-run determinism test; the
  first parse error in path order still wins. [ancora-gg8.7](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gg8.7.json)
- The branch was reconciled with releases 1.1.0 and 1.1.1 through reviewed
  merge commits rather than a rebase; every test and requirement from both
  sides survives. [ancora-gg8.8](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gg8.8.json)

## 1.1.1 - 2026-09-04

### Fixed

- Path traversal: a git tree with an entry literally named `..` made
  `Ancora.BaseView.materialize` write a blob outside its temporary root, and
  the cleanup never removed it. BaseView now rejects the whole tree at
  `tier=env` before any read or write when a path has a `..`, `.`, or empty
  component; `foo..bar` still passes. Reachable only from a local checkout of
  an untrusted repository, since GitHub rejects dot-dot trees on push.
  [ancora-kzw](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-kzw.json)

## 1.1.0 - 2026-09-04

Post-ship hardening: the 66 calibrated findings of the 1.0 critical review,
plus the Critical and High findings of a second review run against this
branch. Three behavior changes a 1.0 repository can meet on upgrade, each
with its remedy in `docs/migration.md`:

- A shallow CI clone whose `base..HEAD` range is incomplete now fails at
  `tier=env` instead of quietly resolving a different verdict; fetch with
  `fetch-depth: 0` or `git fetch --unshallow`. A depth-one clone with its
  parent fetched still passes.
- An ADR `affects:` entry now authorizes append-only edits for the
  requirements it names, not the whole subject.
- A `Spec-Ack:` trailer is a development convenience; `.spec/config.yml` is
  the durable record. The gate warns when a trailer that changes a verdict
  exists only below the branch tip, and the warning clears once config
  carries the same severity.

### Added

- ADRs can retire requirements and subjects through a `retires:` list, the
  only sanctioned way to delete an append-only statement. [ancora-n24](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-n24.json)

### Fixed

- Every environment failure now ends with a verdict line instead of a stack
  trace: unreadable inputs and a closed batch port [ancora-xla.2](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.2.json), an
  unresolvable `--spec-dir` workspace [ancora-41r.4](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.4.json), and every
  malformed git path shape (a quoted name, a missing NUL terminator, an
  invalid name-status or porcelain record, a bad `cat-file --batch` frame)
  [ancora-41r.1](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.1.json). The five task moduledocs now state the real
  `--spec-dir` default, `.spec`.
- Shallow clones: an incomplete range is rejected loudly, boundary parents
  are validated inside the range only, and parent headers are read from the
  commit object rather than the message body. [ancora-11w](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-11w.json)
- Git-supplied paths are read NUL-delimited and never stored quoted; change
  sets resolve base paths to object ids before any blob read, so a file with
  a space or a non-ASCII byte in its name is neither invisible to drift
  detection nor a crash for the batch port. [ancora-41r.1](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.1.json)
- Acknowledgments: the squash-loss warning fires only when removing the
  trailer would change the resolved severity [ancora-sfu](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-sfu.json); when
  commits in the range acknowledge the same code at different severities the
  commit nearest `HEAD` wins [ancora-41r.3](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.3.json); an unknown key in an
  `overrides:` entry is a `config/unknown_key` finding and the entry does not
  apply, and the README no longer instructs a key the parser does not accept
  [ancora-41r.5](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.5.json); the warning goes through the single output layer
  [ancora-xla.6](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.6.json).
- Spec-meta: a malformed block yields one `spec/parse_error` naming the
  rejected field on every corpus-reading task, never a stack trace or three
  false missing-field findings [ancora-xla.1](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.1.json); a spec file with no
  block is one blocking finding and does not count as a checked subject, on
  `spec.check` and `spec.validate` alike [ancora-41r.2](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.2.json).
- The review artifact's verdict chip is the gate verdict of the same run
  [ancora-41r.6](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.6.json); artifact semantics are preserved across the renderer
  rewrite [ancora-xla.4](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.4.json); fanout is bounded and watched diffs are
  deduplicated [ancora-gqb](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gqb.json); vendored assets are pinned and the Prism
  grammar list derives from what ships [ancora-xla.8](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.8.json).
- ADR append authorization is scoped to the requirements an ADR names.
  [ancora-v1n](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-v1n.json)
- CLI and JSON contracts agree, and the duplicate scaffold contract is gone.
  [ancora-xla.5](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.5.json)
- The gate materializes only specs, tests and configured library paths, and
  parses each source once per run; configured `lib_paths` are honored.
  [ancora-xla.3](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.3.json)

### Changed

- Static guards are load-bearing again: the no-direct-IO-writer guard covers
  stderr, the task-count guard watches every Mix task, and ETS-state guards
  observe real runs. [ancora-xla.7](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.7.json) [ancora-xla.9](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.9.json)
- Preflight loads `.spec/config.yml` once and passes the resolved
  `lib_paths` value through; `BaseView.materialize/3` refuses a pre-placed
  root. [ancora-xla.6](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.6.json)

### Removed

- The run-context detector memo and the root-reading review entry points,
  both dead. [ancora-xla.9](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.9.json) [ancora-xla.6](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.6.json)

## 1.0.0 - 2026-09-01

Final 1.0 release.

- Prevent derivation crashes when a variable named `quote` produces a nil AST
  child in real-world source.
- Read multi-expression `project/0` bodies statically when collecting project
  metadata.
- Emit a JSON report when preflight target reads fail in JSON mode.
- Repair the scripts-only replay harness selection and configuration. The M3
  replay validation ritual passed against real Atlas and Builder history at
  this tree.

## 1.0.0-rc.1 - 2026-09-01

First release candidate.

- Add source-derived traceability from tagged ExUnit tests to production
  functions, with growth, shrink, and drift findings across git revisions.
- Add `spec.init`, `spec.prime`, `spec.next`, `spec.status`, `spec.validate`,
  `spec.check`, and the self-contained `spec.review` HTML report.
- Enforce hard-fail environment checks, append-only requirements, spec tag
  coverage, governance co-changes, and a closed finding registry.
- Support human and JSON output through a single output layer with a stable
  verdict line.
