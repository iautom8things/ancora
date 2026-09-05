# Derived Bindings Detector

The change set, project identity, source-derived membership, the per-file
call resolver, clause extraction, canonical comparison, growth and shrink
accounting, and acknowledgment detection. This is ancora's only realization
mechanism: what a subject watches is whatever its tagged tests call.

## Intent

specled_ex asked authors to write `realized_by:` bindings by hand and then
policed them with hashes and a committed baseline. Ancora derives the watched
set from the tagged tests themselves, on both sides of a diff, from source
and git objects alone. No compile artifacts are read, nothing is executed,
and nothing is cached across runs. The detector is pure and symmetric: both
diff sides are parsed by one VM under one Elixir version, so the comparison
can never be skewed by environment.

Modules: `Ancora.Derive`, `Ancora.Derive.ChangeSet`, `Ancora.ProjectInfo`,
`Ancora.Derive.ModuleLocator`, `Ancora.Derive.Membership`,
`Ancora.Derive.DefIndex`, `Ancora.Derive.Resolver`, `Ancora.Derive.Extract`,
`Ancora.Canonical`, `Ancora.Derive.Compare`, `Ancora.Derive.Ack`,
`Ancora.SubjectFiles`, `Ancora.Git`, `Ancora.Git.BatchPort`, `Ancora.BaseView`.

```yaml spec-meta
id: ancora.derive
kind: module
status: active
summary: Source-derived, diff-symmetric detection of what tagged tests call and whether those definitions changed.
decisions:
  - ancora.decision.source_derived_membership
  - ancora.decision.generated_bindings_companion
  - ancora.decision.no_execution_no_state
  - ancora.decision.field_friction_response
  - ancora.decision.no_run_context_memo
```

## Requirements

```yaml spec-requirements
- id: ancora.derive.change_set_union
  statement: >-
    The change set shall be the union of `git diff --name-status --no-renames
    <base>` and `git status --porcelain --untracked-files=all`, as computed
    by Ancora.Derive.ChangeSet. A file inside a new untracked directory shall
    appear individually; a `git mv` followed by an edit shall appear as a
    delete plus an add with both paths prefetched. The gate shall compute no
    change set until preflight confirms that no shallow boundary inside the
    requested `base..HEAD` range has a parent commit absent locally. Both git
    outputs shall be NUL-delimited so path bytes remain unquoted, and a path
    still wrapped in double quotes shall be rejected rather than stored.
  priority: must
  stability: stable
- id: ancora.derive.base_reads_batched
  statement: >-
    Every base-side blob read shall go through one `git cat-file --batch`
    port per run, owned by the run context and never registered under a name.
    Ancora.Git.BatchPort holds that port; Ancora.Git.read_blob/2 is the
    single function head for every base-side blob read, including
    Ancora.BaseView, falling back to per-file `git show` when no port is
    present. Callers shall not open an ephemeral batch port. All base blobs
    a run can need shall be prefetched serially through that port before any
    parallel work begins. The port shall be spawned without
    `stderr_to_stdout` so git stderr can never interleave with blob payloads.
    A fetch timeout, malformed frame, or port exit shall close and poison the
    port; every later fetch through it shall return `{:error, :port_poisoned}`.
    Ancora.BaseView shall return `{:error, :base_required}` when called with a
    repository path and no base. Ancora.Git.run/3 shall return
    `{:error, :git_executable_not_found}` when git is absent instead of raising.
    The no-port `git show` fallback shall also keep stderr separate from the
    returned blob bytes.
    Ancora.BaseView shall read the blob OID returned by `ls-tree`, not rebuild
    `<base>:<path>`, and shall create each materialized parent directory once.
    Before reading any listed blob or creating the materialization root,
    Ancora.BaseView shall reject the entire listed tree with `{:env, message}`
    if any byte-exact path split on `/` contains a `..`, `.`, or empty component.
    Gate.check and Review.build shall propagate this environment failure
    without raising. Legitimate components such as `foo..bar` remain accepted.
    Its root directory name shall use `Ancora.TempName.cross_vm_suffix/0`, and
    it shall create that root with non-recursive `File.mkdir/1` so a pre-existing
    path, including a symlink, returns an error before any blob write.
    The gate's base view shall contain only the configured spec directory,
    configured `test_paths`, and project `lib_paths`. Change-set prefetch shall
    resolve each base path through `git ls-tree` and pass `{:oid, object_id}`
    to `Ancora.Git.read_blob/2` rather than infer its kind from hexadecimal
    text. Ancora.BaseView is the explicit exception: it passes the untagged
    object id returned by `git ls-tree`. The tagged `{:path, path}` form has no
    production caller.
  priority: must
  stability: stable
- id: ancora.derive.memo_is_run_scoped
  statement: >-
    Within one detector run, each changed defining source file shall be parsed
    for extraction at most once per diff side. The gate shall build parsed AST
    maps once across all subjects and pass them to Ancora.Derive.Compare as
    plain function arguments. Extraction reuse shall not use an in-process
    memo, registry, cache, or new process, and shall not persist to disk.
    Ancora.Derive.ModuleLocator shall parse path-sorted library files
    concurrently with ordered collection and pass its per-side AST maps to
    Ancora.Derive.DefIndex, so that leg parses each file once per side and the
    first parse error remains the first one in path order.
    Ancora.Derive.RunContext shall contain only the run root, base, and batch
    port state; starting or stopping it shall not create or delete an ETS table.
  priority: must
  stability: stable
- id: ancora.derive.project_info_from_root
  statement: >-
    Ancora.ProjectInfo shall be resolved once in preflight from the target
    root alone: `app:` and `elixirc_paths:` read as literals from the root
    `mix.exs` via `Code.string_to_quoted`. When `project/0` has leading
    expressions, its last expression shall be read as the return value and
    must be a literal keyword list. A dynamic `elixirc_paths` shall degrade
    to `["lib"]`, overridable by the `lib_paths:` config key; an `apps_path:`
    key shall hard-fail as an umbrella root. Preflight shall pass its resolved
    `lib_paths` value, including nil, into ProjectInfo so ProjectInfo does not
    read `.spec/config.yml` again on that path. A non-literal `app:` shall
    hard-fail with a message. No module downstream of preflight shall read
    `Mix.Project` state. Every `lib_paths` value shall be normalized at
    resolution — trailing slashes trimmed — so all downstream path comparisons
    use one canonical form.
  priority: must
  stability: stable
- id: ancora.derive.membership_source_derived
  statement: >-
    A module M shall be a member on diff side S if and only if
    Ancora.Derive.ModuleLocator finds a `defmodule` or `defprotocol` for M
    under `lib_paths` on side S: HEAD from the working tree, base from the
    same-path base blob and then from the base blobs of change-set files.
    Nested `defmodule` bodies shall be named with their parent prefix.
    When the change set is empty, ModuleLocator shall scan HEAD once and use
    the same module map for base instead of parsing every source file twice.
    Membership shall never read `_build`, any `.app` file, or any compiled
    artifact.
  priority: must
  stability: stable
- id: ancora.derive.qualified_call_disposition
  statement: >-
    A qualified call `Mod.f(args)` whose alias resolves to a member module
    shall enter the call set as `{Mod, :f, arity}`; one resolving to a
    non-member shall be dropped silently. A piped call shall count arity as
    `length(args) + 1` and shall not double-count its left operand. `&Mod.f/2`
    shall resolve like a qualified call at the stated arity. `%Mod{}` struct
    expansion, `use Anything`, and `var.field` no-parens access shall not
    produce bindings. A project-macro DSL invocation shall count as a call to
    the macro module at macro arity.
  priority: must
  stability: stable
- id: ancora.derive.unqualified_ladder
  statement: >-
    An unqualified call `f(args)` shall be disposed in order: present in the
    file's own defs (after default expansion) means silently local; otherwise
    for each import in source order whose `only:`/`except:` admits it, a
    member import target consults that module's DefIndex and a hit resolves
    the binding, while a non-member target is dropped when the tool VM
    exports it; otherwise an export of `Kernel`, `Kernel.SpecialForms`, or
    `ExUnit.{Case,Assertions,Callbacks,DocTest}` is dropped; otherwise the
    call is recorded as unresolved kind `:unqualified`.
  priority: must
  stability: stable
- id: ancora.derive.dynamic_calls_unresolved
  statement: >-
    `apply/2` and `apply/3` shall be recorded as unresolved kind `:apply`
    even when every argument is a literal. `var.f(args)`, `&var.f/2`, and
    `unquote(...)` in call position shall be recorded as unresolved kind
    `:dynamic_module`. Unresolved entries carry file and line and are never
    guessed into bindings.
  priority: must
  stability: stable
- id: ancora.derive.resolver_is_pure
  statement: >-
    Ancora.Derive.Resolver shall perform no I/O and no VM introspection. Its
    context shall be plain data: a per-side membership predicate, the ambient
    export set, and a DefIndex lookup. Ambient-table construction and
    `Code.ensure_loaded?` checks shall live in ctx construction outside the
    resolver, and under `--root` the load path shall never include the target
    project's `_build`. If a resolver callback raises or throws,
    Ancora.Derive.run/2 shall return an error and keep its caller alive.
  priority: must
  stability: stable
- id: ancora.derive.imports_and_aliases
  statement: >-
    Pass A shall collect `import` forms at any depth, including inside
    `setup`, `describe`, and `test` bodies, and apply them module-wide. Pass B
    shall maintain a lexical alias stack handling `alias Foo.Bar`,
    `alias Foo.{Bar, Baz}`, `alias Foo.Bar, as: B`, `alias __MODULE__.Sub`,
    and `require Foo, as: F`, resolving nested segments through the stack
    and then `Module.concat`.
  priority: must
  stability: stable
- id: ancora.derive.parse_degrades_to_finding
  statement: >-
    Detector parsing shall use `Code.string_to_quoted` with default options
    plus `emit_warnings: false` and without `columns:`, `token_metadata:`, or
    `literal_encoder:`. A file that fails to parse on either side shall
    produce `derived/unparseable_source` (error) attributed to the file and
    shall never hard-fail the run.
  priority: must
  stability: stable
- id: ancora.derive.clause_extraction
  statement: >-
    For a binding `{M, f, a}` on one side, extraction shall collect every
    clause whose head defines `{f, a}` after default expansion, across `def`,
    `defmacro`, `defguard`, and `defdelegate`, as one source-ordered list, and
    shall exclude sibling attributes such as `@doc`, `@spec`, and
    `@deprecated`.
  priority: must
  stability: stable
- id: ancora.derive.canonical_is_metadata_strip
  statement: >-
    Ancora.Canonical.normalize/1 shall strip AST metadata and nothing else: no
    alpha-renaming of variables, no folding of charlist or sigil literal
    forms. Two clause lists that differ only in formatting, parentheses,
    do-block style, heredoc style, or numeric underscores shall normalize
    equal; a variable rename or a `~c"x"` versus `'x'` change shall normalize
    unequal.
  priority: must
  stability: stable
- id: ancora.derive.drift_scope_and_dedupe
  statement: >-
    Drift shall be computed only for bindings present on both sides whose
    defining file is in the change set on at least one side; every other
    binding shall be skipped without parsing its module. A definition watched
    at several arities through defaults shall report at most one
    `derived/drift` finding. Ancora.Derive.ChangeSet shall build the changed-path
    MapSet once in `compute/1`, and every comparison shall reuse that set.
  priority: must
  stability: stable
- id: ancora.derive.drift_primary_transitive
  statement: >-
    A drifted binding whose defining file appears in the subject's authored
    `surface:` list shall produce `derived/drift`. When the subject has a
    `surface:` list that omits the defining file, the binding shall produce
    `derived/drift_transitive` at info. A subject without `surface:` shall
    keep the prior behavior and report every drift as `derived/drift`.
  priority: must
  stability: evolving
- id: ancora.derive.growth_and_shrink
  statement: >-
    Per subject, `derived/growth` shall fire when the HEAD set minus the base
    set is nonempty and `derived/shrink` when the base set minus the HEAD set
    is nonempty, each message listing the bindings (capped at 10 with a
    `+N more` suffix). A binding present on HEAD only has no drift.
  priority: must
  stability: stable
- id: ancora.derive.generated_bindings
  statement: >-
    A member-module binding with no textual definition on either side shall
    be classified generated. When the module `use`s a member module, a
    companion binding `{injecting_module, :__using__, 1}` shall enter the
    subject's derived set so macro-body edits fire drift. When the `use`
    target is outside membership, the binding is silent in comparison and
    counted as dep-generated. A binding textual on one side and
    generated or absent on the other, with the module in membership and tests
    still calling it, shall fire `derived/drift` with the message
    "definition moved into or out of macro-generated code".
  priority: must
  stability: evolving
- id: ancora.derive.acknowledgment_is_substantive
  statement: >-
    Ancora.Derive.Ack shall report a subject acknowledged when the parsed
    requirement list or scenario list of its spec file differs between base
    and HEAD after collapsing internal whitespace in every string value.
    Edits confined to spec-meta, prose, or whitespace shall not acknowledge;
    any entry added, removed, or field-changed shall.
  priority: must
  stability: stable
- id: ancora.derive.subject_footprint
  statement: >-
    A subject's file footprint shall be the union of its tagged test files
    and the defining files of its derived bindings; no other mapping from
    subject to file shall exist.
  priority: must
  stability: stable
- id: ancora.derive.formatter_round_trip
  statement: >-
    For every source file in the ancora repository, resolving the file and
    resolving `Code.format_string!/1` of the file shall yield identical call
    sets, and normalizing the extracted clauses of both shall be equal.
  priority: should
  stability: evolving
```

## Scenarios

```yaml spec-scenarios
- id: ancora.derive.scenario.new_dir_new_test_is_growth
  given:
    - a tmp git repo with a subject whose tagged test calls `Billing.next/1`
    - on HEAD a new untracked directory `test/billing/` containing a new tagged test calling `Billing.void/2`
  when:
    - the detector runs against the prior commit
  then:
    - the change set contains `test/billing/void_test.exs`
    - `derived/growth` fires for the subject naming `Billing.void/2`
  covers:
    - ancora.derive.change_set_union
    - ancora.derive.growth_and_shrink
- id: ancora.derive.scenario.moved_module_is_delete_plus_add
  given:
    - `lib/a.ex` is moved to `lib/b.ex` and one function body edited
  when:
    - the change set is computed
  then:
    - `lib/a.ex` appears as deleted and `lib/b.ex` as added
    - both base blobs are prefetched through the batch port
  covers:
    - ancora.derive.change_set_union
    - ancora.derive.base_reads_batched
- id: ancora.derive.scenario.git_paths_round_trip
  given:
    - changed tracked library files whose names contain UTF-8 bytes or spaces
    - an untracked file whose name contains a space
  when:
    - the gate computes and prefetches the change set
  then:
    - every path remains byte-identical to the name supplied by git
    - committed paths resolve to object ids before blob reads
    - a hexadecimal path tagged as a path is never treated as an object id
  covers:
    - ancora.derive.change_set_union
    - ancora.derive.base_reads_batched
- id: ancora.derive.scenario.incomplete_range_stops_before_change_set
  given:
    - a shallow clone with a boundary inside `base..HEAD` whose parent is absent locally
  when:
    - the gate runs
  then:
    - the gate returns an environment failure before Ancora.Derive.ChangeSet computes
  covers:
    - ancora.derive.change_set_union
- id: ancora.derive.scenario.batch_port_frames
  given:
    - a captured `git cat-file --batch` byte stream containing three blobs, one of size zero
  when:
    - the frame parser consumes it
  then:
    - three payloads are returned with the correct sizes and oids
    - framing is `<oid> <type> <size>\n<payload>\n`
  covers:
    - ancora.derive.base_reads_batched
- id: ancora.derive.scenario.batch_port_timeout_poison
  given:
    - a batch fetch that receives no complete frame before its timeout
  when:
    - another fetch is attempted through the same port
  then:
    - the port is closed
    - the later fetch returns `{:error, :port_poisoned}` instead of stale bytes
  covers:
    - ancora.derive.base_reads_batched
- id: ancora.derive.scenario.no_port_stderr_isolated
  given:
    - a run without a batch port whose successful `git show` emits a warning on stderr
  when:
    - Ancora.Git.read_blob/2 reads a committed blob
  then:
    - the returned payload contains only the committed blob bytes
    - the warning remains on stderr
  covers:
    - ancora.derive.base_reads_batched
- id: ancora.derive.scenario.two_concurrent_runs_do_not_collide
  given:
    - two detector runs started concurrently in the same VM against different roots
  when:
    - both complete
  then:
    - neither run observes the other's parsed-source arguments
    - each run's parsed-source maps are plain data and its batch port is unregistered
  covers:
    - ancora.derive.memo_is_run_scoped
- id: ancora.derive.scenario.narrowed_base_materialization
  given:
    - a base tree containing files under the configured spec directory, configured test and library paths, and an unrelated directory
  when:
    - the gate materializes its base view
  then:
    - only the spec, test, and library files exist in the materialized tree
    - each blob is read by its `ls-tree` OID
    - each shared parent directory is created once
  covers:
    - ancora.derive.base_reads_batched
- id: ancora.derive.scenario.extraction_parses_once_per_side
  given:
    - two subjects watching several definitions in one changed source file
  when:
    - the gate compares both subjects
  then:
    - the source file is parsed for extraction once at base and once at HEAD
    - both comparisons receive the same parsed-source maps as arguments
  covers:
    - ancora.derive.memo_is_run_scoped
- id: ancora.derive.scenario.dynamic_elixirc_paths_degrade
  given:
    - "a target `mix.exs` with `elixirc_paths: elixirc_paths(Mix.env())`"
    - no `lib_paths:` in config
  when:
    - ProjectInfo is resolved
  then:
    - `lib_paths` is `["lib"]`
  covers:
    - ancora.derive.project_info_from_root
- id: ancora.derive.scenario.leading_project_expression
  given:
    - "a target `project/0` that calls a setup function before returning a literal keyword list"
  when:
    - ProjectInfo is resolved
  then:
    - the literal `app:` is read from the final list expression
    - the setup function is never evaluated
  covers:
    - ancora.derive.project_info_from_root
- id: ancora.derive.scenario.umbrella_root_hard_fails
  given:
    - "a target `mix.exs` with `apps_path: \"apps\"`"
  when:
    - preflight runs
  then:
    - the run hard-fails with `tier=env` and a message naming umbrella roots as unsupported
  covers:
    - ancora.derive.project_info_from_root
- id: ancora.derive.scenario.trailing_slash_lib_path
  given:
    - '`lib_paths: ["src/"]` with `src/legacy.ex` defining `Legacy` at base and deleted on HEAD'
  when:
    - membership is computed per side
  then:
    - `Legacy` is a member at base and not at HEAD
    - the change-set file is not dropped from base membership
  covers:
    - ancora.derive.project_info_from_root
    - ancora.derive.membership_source_derived
    - ancora.derive.subject_footprint
- id: ancora.derive.scenario.deleted_module_visible_at_base
  given:
    - `lib/legacy.ex` defining `Legacy` exists at base and is deleted on HEAD
    - a tagged test at base called `Legacy.run/0`
  when:
    - membership is computed per side
  then:
    - `Legacy` is a member at base and not at HEAD
    - `derived/shrink` fires naming `Legacy.run/0`
  covers:
    - ancora.derive.membership_source_derived
    - ancora.derive.growth_and_shrink
- id: ancora.derive.scenario.nested_and_protocol_modules
  given:
    - a lib file with `defmodule Outer do defmodule Inner do ... end end` and a `defprotocol Shape`
  when:
    - the locator scans HEAD
  then:
    - `Outer`, `Outer.Inner`, and `Shape` are all members
  covers:
    - ancora.derive.membership_source_derived
- id: ancora.derive.scenario.disposition_table_rows
  given:
    - "one fixture test file per construct row: qualified member call, qualified dep call, pipe, remote capture, local capture, `apply/3` with literals, `var.f()`, `var.field`, struct literal, `use`, project-macro DSL call, `unquote` in call position, unqualified local helper, unqualified member import, unqualified `import Ecto.Query` function, `assert`"
  when:
    - each file is resolved with a fixed data-only ctx
  then:
    - the member call, pipe, remote capture, and member import resolve to bindings at the stated arities
    - the dep call, `var.field`, struct literal, `use`, Ecto import, and `assert` produce no binding and no unresolved entry
    - `apply/3` is unresolved kind `:apply`; `var.f()` and `unquote` are unresolved kind `:dynamic_module`
    - the DSL call binds to the macro module at macro arity
    - the local helper produces nothing
  covers:
    - ancora.derive.qualified_call_disposition
    - ancora.derive.unqualified_ladder
    - ancora.derive.dynamic_calls_unresolved
- id: ancora.derive.scenario.import_inside_test_block
  given:
    - a test file whose only `import MyApp.Helpers` sits inside a `test` body and a later test calls `helper/1` unqualified
  when:
    - the file is resolved with `MyApp.Helpers` in membership and its DefIndex exporting `helper/1`
  then:
    - `{MyApp.Helpers, :helper, 1}` is in the call set
  covers:
    - ancora.derive.imports_and_aliases
    - ancora.derive.unqualified_ladder
- id: ancora.derive.scenario.alias_stack_round_trip
  given:
    - "stream_data generated modules nesting `alias Foo.Bar, as: B`, `alias Foo.{Baz, Qux}`, and `__MODULE__` frames around a qualified call"
  when:
    - each generated source is resolved
  then:
    - the call resolves to the fully qualified module the generator intended
  covers:
    - ancora.derive.imports_and_aliases
- id: ancora.derive.scenario.resolver_never_touches_io
  given:
    - a resolver invocation with a ctx whose membership predicate and DefIndex lookup are plain functions over maps
  when:
    - the file is resolved
  then:
    - no file, port, or `Code.ensure_loaded?` call occurs inside the resolver
    - "the resolver test module is `async: true`"
  covers:
    - ancora.derive.resolver_is_pure
- id: ancora.derive.scenario.resolver_callback_raises
  given:
    - a resolver context whose membership callback raises
  when:
    - Ancora.Derive.run/2 resolves a file that calls a member module
  then:
    - the run returns `{:error, {:resolver_exception, path, message}}`
    - the caller remains alive
  covers:
    - ancora.derive.resolver_is_pure
- id: ancora.derive.scenario.unparseable_base_file
  given:
    - a defining file that is valid on HEAD but syntactically broken at base
  when:
    - drift is computed for a binding it defines
  then:
    - `derived/unparseable_source` fires naming the file and the base side
    - the run completes and the verdict line is emitted
  covers:
    - ancora.derive.parse_degrades_to_finding
- id: ancora.derive.scenario.canonical_table
  given:
    - pairs of clause lists that differ only in parentheses, `do:` versus do-block, heredoc versus string, numeric underscores, and whitespace
    - pairs that differ by variable rename, by `'abc'` versus `~c"abc"`, and by clause reorder
  when:
    - each pair is normalized and compared
  then:
    - the first group compares equal
    - the second group compares unequal
  covers:
    - ancora.derive.canonical_is_metadata_strip
- id: ancora.derive.scenario.defdelegate_retarget_fires
  given:
    - "a watched `defdelegate next(x), to: Billing.V1` changed to `to: Billing.V2` in the change set"
  when:
    - drift is computed
  then:
    - `derived/drift` fires once for `Billing.next/1`
  covers:
    - ancora.derive.clause_extraction
    - ancora.derive.drift_scope_and_dedupe
- id: ancora.derive.scenario.doc_only_edit_is_quiet
  given:
    - a watched function whose only change is its `@doc` string
  when:
    - drift is computed
  then:
    - no `derived/drift` fires
  covers:
    - ancora.derive.clause_extraction
- id: ancora.derive.scenario.default_arity_reports_once
  given:
    - `def foo(a, b \\ 1)` watched as both `foo/1` and `foo/2` with its body changed
  when:
    - drift is computed
  then:
    - exactly one `derived/drift` finding names `foo`
  covers:
    - ancora.derive.drift_scope_and_dedupe
- id: ancora.derive.scenario.unchanged_file_not_parsed
  given:
    - a watched binding whose defining file is outside the change set
  when:
    - drift is computed
  then:
    - the defining file is never parsed for extraction
  covers:
    - ancora.derive.drift_scope_and_dedupe
- id: ancora.derive.scenario.transitive_drift_outside_surface
  given:
    - a shared binding drifts and a subject reaches it transitively
    - the subject's `surface:` list omits the binding's defining file
  when:
    - drift is computed
  then:
    - `derived/drift_transitive` fires at info
  covers:
    - ancora.derive.drift_primary_transitive
- id: ancora.derive.scenario.primary_drift_inside_surface
  given:
    - a shared binding drifts and a subject reaches it
    - the binding's defining file appears in the subject's `surface:` list
  when:
    - drift is computed
  then:
    - `derived/drift` fires
  covers:
    - ancora.derive.drift_primary_transitive
- id: ancora.derive.scenario.no_surface_keeps_primary_drift
  given:
    - a shared binding drifts and a subject has no `surface:` field
  when:
    - drift is computed
  then:
    - `derived/drift` fires
  covers:
    - ancora.derive.drift_primary_transitive
- id: ancora.derive.scenario.macro_injected_api_drifts_via_companion
  given:
    - a member module `MyApp.Schema` whose `__using__/1` injects `changeset/2` into `MyApp.User`
    - a tagged test calls `MyApp.User.changeset/2`
    - the quoted body inside `MyApp.Schema.__using__/1` changes in the diff
  when:
    - the detector runs
  then:
    - `{MyApp.Schema, :__using__, 1}` is in the subject's derived set
    - `derived/drift` fires for the subject
  covers:
    - ancora.derive.generated_bindings
- id: ancora.derive.scenario.repo_insert_stays_silent
  given:
    - a tagged test calling `MyApp.Repo.insert/1` where `MyApp.Repo` only `use`s `Ecto.Repo`
  when:
    - the detector runs
  then:
    - the binding is counted as dep-generated
    - no finding names `MyApp.Repo.insert/1`
  covers:
    - ancora.derive.generated_bindings
- id: ancora.derive.scenario.def_moved_into_use_is_drift
  given:
    - `MyApp.User.changeset/2` is a textual def at base and is macro-injected on HEAD, with the tagged test still calling it
  when:
    - the detector runs
  then:
    - `derived/drift` fires with message containing "moved into or out of macro-generated code"
  covers:
    - ancora.derive.generated_bindings
- id: ancora.derive.scenario.whitespace_never_acknowledges
  given:
    - stream_data whitespace-only mutations of a spec file's requirement block
    - one generated word-level edit to a requirement statement
  when:
    - Ack compares base and HEAD for each
  then:
    - every whitespace-only mutation is not substantive
    - the word-level edit is substantive
  covers:
    - ancora.derive.acknowledgment_is_substantive
- id: ancora.derive.scenario.meta_edit_does_not_acknowledge
  given:
    - a spec file whose only change is a new `summary:` in spec-meta
  when:
    - Ack compares
  then:
    - the subject is not acknowledged
  covers:
    - ancora.derive.acknowledgment_is_substantive
- id: ancora.derive.scenario.footprint_union
  given:
    - a subject with tagged tests in `test/a_test.exs` whose calls resolve to defs in `lib/a.ex` and `lib/b.ex`
  when:
    - SubjectFiles is computed
  then:
    - the footprint is exactly `test/a_test.exs`, `lib/a.ex`, `lib/b.ex`
  covers:
    - ancora.derive.subject_footprint
- id: ancora.derive.scenario.own_corpus_round_trip
  given:
    - every `.ex` and `.exs` file under ancora's `lib/` and `test/`
  when:
    - each file is resolved raw and after `Code.format_string!/1`
  then:
    - the two call sets are equal for every file
  covers:
    - ancora.derive.formatter_round_trip
```

## Verification

```yaml spec-verification
- kind: tagged_tests
  covers:
    - ancora.derive.change_set_union
    - ancora.derive.base_reads_batched
    - ancora.derive.memo_is_run_scoped
    - ancora.derive.project_info_from_root
    - ancora.derive.membership_source_derived
    - ancora.derive.qualified_call_disposition
    - ancora.derive.unqualified_ladder
    - ancora.derive.dynamic_calls_unresolved
    - ancora.derive.resolver_is_pure
    - ancora.derive.imports_and_aliases
    - ancora.derive.parse_degrades_to_finding
    - ancora.derive.clause_extraction
    - ancora.derive.canonical_is_metadata_strip
    - ancora.derive.drift_scope_and_dedupe
    - ancora.derive.drift_primary_transitive
    - ancora.derive.growth_and_shrink
    - ancora.derive.generated_bindings
    - ancora.derive.acknowledgment_is_substantive
    - ancora.derive.subject_footprint
    - ancora.derive.formatter_round_trip
```
