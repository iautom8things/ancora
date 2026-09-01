# Replay selection

This set is for the Manuel-supervised M3 go or no-go run. Each drift case is a squash-merge commit whose parent is the PR base. The harness checks the commit as HEAD and its first parent as `--base`.

Run the self-test first. It must prove exit 0 for a synthetic body change, exit 1 when a formatting commit is presented as drift, and exit 2 for invalid JSON.

```sh
mix run scripts/replay/self_test.exs
mix run scripts/replay/exit_state_test.exs
mix run scripts/replay/replay.exs -- \
  --atlas-repo /path/to/atlas \
  --builder-repo /path/to/builder
```

The machine-readable set is [`selection.tsv`](selection.tsv). The harness overwrites only the detached temporary worktree's `.spec/config.yml`. It does not compile either consumer checkout.

The replay gate runs under Ancora's own Elixir and Erlang versions. Manuel dropped target-toolchain execution on 2026-09-01 because `spec.check` reads the target's files and git history without compiling it.

## Drift cases

| Case | Commit | Changed public function called by a tagged test | Evidence |
| --- | --- | --- | --- |
| [Atlas PR 70](https://github.com/ChapterSpot/atlas/pull/70) | `f45847fe156b2cc406453a63fb22d5ab979adca7` | `Atlas.KB.RepoCentralization.merge_plan/1` | `test/atlas/kb/repo_centralization_test.exs` calls it under `repo.central.attachment_id_stability`; the PR changes the sort comparator and has no `.spec/specs/` edit. |
| [Atlas PR 71](https://github.com/ChapterSpot/atlas/pull/71) | `083c31e99c32c000e992911b2ff912cee33861f8` | `Atlas.KB.RepoCentralization.merge_plan/1` | The tagged attachment-stability test calls it with raw UUIDs; the function now normalizes those values. No `.spec/specs/` file changed. |
| [Atlas PR 109](https://github.com/ChapterSpot/atlas/pull/109) | `77b7154faab04b48319af6be66bf5d270e08f8a8` | `Atlas.Extractor.Staleness.list_stale_node_ids/1` | A `versioning.extractor_staleness_check` test calls the default-argument arity directly after its shared repo-scoping definition changed. No `.spec/specs/` file changed. |
| [Atlas PR 143](https://github.com/ChapterSpot/atlas/pull/143) | `0735362a100b7aed7aa115a6d199cef16a8bd905` | `Atlas.Slack.Attachments.files_for_event/3` | `test/atlas/slack/attachments_test.exs` calls it directly under `slack.image_attachments.app_mention_files_fallback`; the PR replaces its app-mention body with delegation to the new explicit-trigger lookup. No `.spec/specs/` file changed. |
| [Builder PR 59](https://github.com/ChapterSpot/builder/pull/59) | `95faa605fa992ee38b2467d08eb1e91c47339ffd` | `Builder.Agent.ConfigEditor.SnapshotStore.alive?/2`, `Builder.Application.Sentry.before_send/1` | Tagged tests call both changed functions directly. The PR has no `.spec/specs/` edit. |

The selection excludes the `vzd.4` shared-helper fan-out class. A tagged test calling a stable public function does not make a private helper body visible to direct-only derivation.

## Control

Atlas commit `d885921177f629f2e931020c392f8f9f9543e66a` is the repository's plain `chore: mix format pass`. It predates Atlas's pull-request-only workflow, so GitHub has no PR number for it. It used ordinary `mix format`, not `mix format --migrate`, and changes no behavior. Atlas's corpus at this commit is unmigrated, so the replay config silences `derived/unanchored_subject` and `change/uncovered_file`. Both fire for any commit pair in that corpus and say nothing about formatting versus drift. The control passes only when the report has no warning-or-error `derived/*` or `change/*` findings after excluding `derived/unresolved_calls` and `format/retired_construct` by exact code.
