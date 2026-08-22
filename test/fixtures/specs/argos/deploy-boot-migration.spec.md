# Deploy — Self-Migrating Schema on Boot

A deployed Argos release had no migrate step anywhere: the container CMD is
`bin/argos start`, `ci/k8s-config.yaml.erb` defines no migrate `Job` and no
init container, `deploy.yaml` never migrates, and `Argos.Release.migrate/0`
had no automated caller. Dev never notices because the compose web command
chains `mix argos.setup` into `phx.server`, so every dev boot migrates — but
the first production deploy would boot against whatever schema happens to be
there.

Two constraints make the argos version of the fleet's self-migrating-boot
pattern different from atlas's. First, the runtime role deliberately cannot
execute DDL — `Argos.Repo.assert_runtime_role!/0` guarantees it owns no
covered table — so migrations run over `Argos.MigrationRepo`, a separate
owner-credentialed connection, and the migrating and serving roles must
differ. Second, two files under `priv/repo` guarded dev-only DDL and seeds
with `Mix.env()`, and Mix does not ship in a release: the first boot-time
migration run would have crashed on `UndefinedFunctionError` before the guard
could evaluate. The environment predicate is the runtime `:argos, :env`
application config (`config :argos, env: config_env()`), never `Mix.env()`.

```spec-meta
id: deploy.boot_migration
kind: policy
status: draft
summary: "Argos.Repo.Migrator is a one-shot supervisor child that applies all pending migrations at application boot in deployed environments, running over Argos.MigrationRepo — an owner-credentialed connection configured from ARGOS_MIGRATION_DATABASE_URL, whose role must differ from DATABASE_URL's runtime role, which deliberately cannot DDL. The child sits ahead of Argos.Repo: on a fresh database the migrations create the group roles, the argos_oban schema, and every table, so nothing connecting as the runtime role may start first. It is gated by :auto_migrate_on_boot (the ARGOS_AUTO_MIGRATE kill switch), defaulting to Application.fetch_env!(:argos, :env) in [:prod, :staging]; in dev/test it is a no-op because mix argos.setup and the SQL sandbox own the schema. boot_migrate!/0 returns :ignore so the supervisor treats it as a completed one-shot; a failing migration raises, the app does not start, and the rollout stalls behind maxUnavailable: 0 while the previous ReplicaSet serves. Everything under priv/repo must be release-safe: no Mix.* calls, env guards in Application-config membership form."
surface:
  - lib/argos/repo/migrator.ex
  - lib/argos/migration_repo.ex
  - lib/argos/application.ex
  - lib/argos/release.ex
  - lib/argos/repo/migration/sql_file.ex
  - config/runtime.exs
  - priv/repo/migrations/20260811999999_load_hcxjanus_structure.exs
  - priv/repo/migrations/20260814000000_install_oban_persistence.exs
  - priv/repo/workforce_seeds.exs
  - ci/k8s-config.yaml.erb
  - test/support/boot_test_helpers.ex
  - test/support/migrator_probe_repo.ex
  - test/support/migrator_probe_migration.ex
  - test/support/migrator_probe_failing_migration.ex
decisions:
  - argos.decision.boot_automigration
  - argos.decision.test_nonvacuity
  - argos.decision.migration_slices
```

```spec-requirements
- id: deploy.boot_migration.public_schema_migrated_on_boot
  priority: must
  statement: >
    At application boot in a deployed environment, Argos.Repo.Migrator.boot_migrate!/0
    must apply all pending migrations via Ecto.Migrator over Argos.MigrationRepo, wired
    into Argos.Application.children/1 as a one-shot child positioned ahead of Argos.Repo
    — on a fresh database the migrations themselves create the group roles, the
    argos_oban schema, and every table, so nothing that connects as the runtime role may
    start first — and before the Oban children, whose DynamicQueues plugin resolves
    queue configuration against data_source at startup. It must return :ignore so the
    supervisor records a completed step rather than a long-lived process.
    Argos.Release.migrate/0 remains the operator's manual fallback and must share the
    same implementation and the same migration connection, so the two paths cannot
    diverge. The migration set must be self-sufficient: it installs the Oban tables
    (argos_oban) as well as the public schema, because no other channel exists in a
    release.

- id: deploy.boot_migration.migration_role_differs
  priority: must
  statement: >
    Migrations must run as the schema-owner role, never as the runtime role: the
    runtime role deliberately cannot execute DDL and must never come to own a covered
    table (Argos.Repo.assert_runtime_role!/0 raises on ownership). Argos.MigrationRepo
    is configured from ARGOS_MIGRATION_DATABASE_URL in deployed environments; boot must
    refuse a missing ARGOS_MIGRATION_DATABASE_URL and must refuse a migration role
    identical to DATABASE_URL's role, at config time, before any connection is
    attempted. The slice executor (SqlFile.execute_slice!/3) must take its connection
    from the repo actually running the migration, so slice DDL cannot silently fall
    back to the runtime role's credentials.

- id: deploy.boot_migration.disabled_outside_deployed
  priority: must
  statement: >
    Boot-time auto-migration must be gated by the :auto_migrate_on_boot application
    env, settable at runtime via the ARGOS_AUTO_MIGRATE environment variable and
    defaulting to the runtime predicate Application.fetch_env!(:argos, :env) in
    [:prod, :staging]. Under :dev and :test the default must therefore be false — the
    schema is owned by mix argos.setup and the Ecto SQL sandbox — and an explicit
    setting must take precedence over the default in any environment. When disabled,
    boot_migrate!/0 must still return :ignore without touching the database.

- id: deploy.boot_migration.failure_semantics
  priority: must
  statement: >
    A failing boot migration must raise out of boot_migrate!/0 un-rescued: the
    supervisor start fails, Application.start/2 fails, the Endpoint never binds, and
    the pod never passes its startupProbe. The rollout then stalls behind the
    manifest's maxUnavailable: 0 while the previous ReplicaSet keeps serving, so a bad
    migration is a stalled deploy, not an outage. Recovery is fix-forward; a slice
    applied but not recorded (the version row commits on a different connection than
    the slice batch) is repaired with mix argos.schema.repair. Rollback past a
    forward-only migration is a restore-from-backup operation, and
    Argos.Release.rollback/2 is scoped in practice to reversible migrations.

- id: deploy.boot_migration.rollout_compatibility
  priority: should
  statement: >
    Because the new pod migrates while the previous ReplicaSet still serves (maxSurge 1,
    maxUnavailable 0), a migration should keep the previous image's queries valid for
    the duration of the rollout (expand/contract), and the migration connection must
    carry a bounded lock_timeout so a migration blocked on a lock held by live traffic
    fails visibly and retries instead of queueing the old pods' queries behind an
    ACCESS EXCLUSIVE request while they still report healthy.

- id: deploy.boot_migration.multi_replica_safe
  priority: must
  statement: >
    Concurrent replica boots must serialize such that each migration applies exactly
    once: Ecto.Migrator holds a lock on the migration ledger for the duration of the
    run on a connection separate from the DDL, and a replica that arrives second
    blocks, then finds nothing pending. The implementation must not add a second,
    conflicting locking scheme. The k8s manifest must give boot the migration window: a
    startupProbe must own pod startup so the liveness probe cannot kill a pod that is
    mid-migration, and the Deployment's progressDeadlineSeconds must be derived from
    the same budget so the controller cannot mark a legitimately migrating rollout
    failed before the kubelet gives up on it.

- id: deploy.boot_migration.release_safe_guards
  priority: must
  statement: >
    Nothing under priv/repo may call into Mix — releases do not ship Mix, and the
    boot migrator evaluates these files in a release. Environment-guarded migrations
    and seed scripts must use the runtime predicate Application.fetch_env!(:argos,
    :env) in membership form, preserving the prod-and-staging membership contract of
    platform.dev_env.workforce_structure_is_env_guarded. The absence of Mix references
    under priv/repo is itself asserted by a corpus-non-empty scanning test, because the
    failure it prevents is a prod-only boot crash that no dev or CI run can reach.

- id: deploy.boot_migration.migration_versions_are_unique
  priority: must
  statement: >
    A migration's version stamp must be unique within the branch and against every stamp
    already on origin/main. Ecto records a version once: a second file carrying a version
    already recorded is marked applied and never runs — silently, in production, with the
    schema change simply absent. The check runs in CI and as `make check-migration-versions`,
    on the host shell alone (git and coreutils, no BEAM and no compose) so CI runs the
    identical target, and it fails the build rather than reporting.
```

```spec-scenarios
- id: deploy.boot_migration.sc_disabled_in_test_is_noop
  covers:
    - deploy.boot_migration.disabled_outside_deployed
  given:
    - The application is running under MIX_ENV=test with no :auto_migrate_on_boot override
  when:
    - Argos.Repo.Migrator.enabled?/0 is evaluated and boot_migrate!/0 is invoked
  then:
    - enabled?/0 returns false
    - boot_migrate!/0 returns :ignore without running migrations

- id: deploy.boot_migration.sc_deployed_env_defaults_on
  covers:
    - deploy.boot_migration.disabled_outside_deployed
  given:
    - The :argos :env application config reports :prod or :staging and no :auto_migrate_on_boot setting exists
  when:
    - Argos.Repo.Migrator.enabled?/0 is evaluated
  then:
    - enabled?/0 returns true

- id: deploy.boot_migration.sc_explicit_setting_wins
  covers:
    - deploy.boot_migration.disabled_outside_deployed
  given:
    - The :auto_migrate_on_boot application env is set (as ARGOS_AUTO_MIGRATE sets it)
  when:
    - Argos.Repo.Migrator.enabled?/0 is evaluated for true and for false
  then:
    - enabled?/0 reflects the explicit value, overriding the environment default

- id: deploy.boot_migration.sc_migrate_path_executes
  covers:
    - deploy.boot_migration.public_schema_migrated_on_boot
  given:
    - A schema-prefixed probe repo and a pending probe migration
  when:
    - Argos.Repo.Migrator.migrate!/2 and the enabled boot_migrate!/2 run against it
  then:
    - The migration is applied and recorded in the probe schema's ledger
    - boot_migrate!/2 returns :ignore and migrate!/2 returns :ok
    - The probe repo is stopped after the run

- id: deploy.boot_migration.sc_failing_migration_fails_boot
  covers:
    - deploy.boot_migration.failure_semantics
  given:
    - An enabled migrator and a migration that raises
  when:
    - boot_migrate!/2 runs
  then:
    - The raise propagates un-rescued out of the boot path

- id: deploy.boot_migration.sc_boot_refuses_shared_role
  covers:
    - deploy.boot_migration.migration_role_differs
  given:
    - A deployed configuration whose ARGOS_MIGRATION_DATABASE_URL names DATABASE_URL's role, or is missing
  when:
    - config/runtime.exs is evaluated
  then:
    - The boot raises naming the problem before any connection is attempted
    - The manifest maps ARGOS_MIGRATION_DATABASE_URL from the Terraform-managed argos-<env>-database Secret

- id: deploy.boot_migration.sc_child_sits_ahead_of_repo_and_oban
  covers:
    - deploy.boot_migration.public_schema_migrated_on_boot
  given:
    - Argos.Application.children/1 evaluated for a deployed environment
  when:
    - The child list is inspected
  then:
    - Argos.Repo.Migrator appears exactly once, ahead of Argos.Repo, the Oban child, and ArgosWeb.Endpoint

- id: deploy.boot_migration.sc_priv_repo_is_mix_free
  covers:
    - deploy.boot_migration.release_safe_guards
  given:
    - The source of every .exs file under priv/repo
  when:
    - The sources are scanned for Mix references and the guard predicates are inspected
  then:
    - The scan corpus is non-empty and no file references Mix
    - "The hcxjanus structure migration and workforce_seeds.exs guard on Application.fetch_env!(:argos, :env) in [:prod, :staging]"

- id: deploy.boot_migration.sc_duplicate_version_stamp_fails_the_build
  covers:
    - deploy.boot_migration.migration_versions_are_unique
  given:
    - A branch adding a migration whose version stamp is already used, in the branch or on origin/main
  when:
    - check-migration-versions runs
  then:
    - It names the colliding files and exits non-zero
    - A branch whose stamps are all unique exits zero

- id: deploy.boot_migration.sc_startup_probe_owns_the_boot_window
  covers:
    - deploy.boot_migration.multi_replica_safe
    - deploy.boot_migration.rollout_compatibility
  given:
    - The rendered k8s manifest for the web tier
  when:
    - The probe and rollout configuration are inspected
  then:
    - A startupProbe is defined whose window (periodSeconds x failureThreshold) equals the boot-migration budget
    - progressDeadlineSeconds is derived from the same budget and is at least the window
    - Liveness and readiness probing begin only after the startupProbe passes
```

```spec-verification
- kind: command
  target: make check-migration-versions
  execute: false
  covers:
    - deploy.boot_migration.migration_versions_are_unique

- kind: command
  target: mix test test/argos/repo/migrator_test.exs
  execute: true
  covers:
    - deploy.boot_migration.public_schema_migrated_on_boot
    - deploy.boot_migration.disabled_outside_deployed
    - deploy.boot_migration.failure_semantics

- kind: command
  target: mix test test/argos/deploy/boot_assertions_test.exs
  execute: true
  covers:
    - deploy.boot_migration.migration_role_differs

- kind: command
  target: mix test test/argos/deploy/derived_config_test.exs
  execute: true
  covers:
    - deploy.boot_migration.multi_replica_safe
    - deploy.boot_migration.rollout_compatibility

- kind: command
  target: mix test test/argos/deploy/release_safe_guards_test.exs
  execute: true
  covers:
    - deploy.boot_migration.release_safe_guards

- kind: source_file
  target: ci/k8s-config.yaml.erb
  execute: false
  covers:
    - deploy.boot_migration.multi_replica_safe
```
