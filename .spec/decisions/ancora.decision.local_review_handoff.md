---
id: ancora.decision.local_review_handoff
status: accepted
date: 2026-11-13
affects:
  - ancora.review
  - ancora.review.reuses_check_result
  - ancora.gate.no_derived_state
---

# spec.check hands its gate result to spec.review through _build

## Context

The shared CI workflow runs `mix spec.check --base <base>` and then
`mix spec.review --base <base>` on every PR, in separate VMs. Review needs the
same gate result check just computed, so it ran the whole gate a second time.
On Argos with ancora 1.3.1 and four schedulers that second run was about 20 of
review's 24 seconds.

`ancora.decision.no_execution_no_state` said no derived state is written. Its
target was specled_ex's committed baselines, which drifted between branches
and were regenerated to make conflicts go away. Manuel ruled on 2026-11-13
that the rule was overstated: it exists to keep maintained state out of
version control, and local uncommitted state that speeds up CI is acceptable.

## Decision

- `spec.check` stores the fields review reads at `_build/ancora/gate.etf`,
  only when git ignores that path, so the file cannot be committed.
- The file's key fingerprints every gate input: ancora's module checksums and
  dependency versions, the toolchain, the root and spec directory, the base and
  HEAD commit ids, and the content of every dirty, untracked or (under the
  scanned paths) ignored file. Check takes the key before and after its run
  and stores nothing if they differ.
- `spec.review` uses the file only on an exact key match. Any miss, including
  a missing, truncated or malformed file, reruns the gate.
- `spec.check` never reads the file. Every gate verdict still comes from the
  working tree plus git objects.

## Consequences

Positive: a PR's review step drops from a full gate run to reading one file.
On Argos it goes from about 24 seconds to about 4. `spec.check` pays nothing
measurable for the write.

Negative: review results now depend on a cache key being complete. An input
the key misses would serve a stale review artifact, though never a wrong gate
verdict. The file is about 30 MB on Argos, and a repository that does not
ignore `_build` gets no speedup.
