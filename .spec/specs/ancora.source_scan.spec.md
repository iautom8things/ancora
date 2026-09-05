# Source scan

`Ancora.SourceScan` is a test-support helper for consumer-owned forbidden-text
tripwires. It reads the consumer's working tree when its tagged ExUnit tests
run. It is not part of an Ancora gate task.

## Intent

Keep the common source-scan case small without bringing command execution back
into Ancora. The helper owns the two easy-to-miss correctness rules: an empty
file set fails, and plain strings do not match inside longer identifiers.

```yaml spec-meta
id: ancora.source_scan
kind: module
status: active
summary: A file-only source scanner for consumer-owned tagged ExUnit tripwires.
decisions:
  - ancora.decision.field_friction_response
  - ancora.decision.no_execution_no_state
```

## Requirements

```yaml spec-requirements
- id: ancora.source_scan.declarative_config
  statement: >-
    `Ancora.SourceScan.scan/1` shall take directories or globs, forbidden tokens
    expressed as strings or regular expressions, and an allowlist of paths, and
    shall return violations as `{file, line, token}` tuples.
  priority: must
  stability: stable
- id: ancora.source_scan.vacuity_guard
  statement: >-
    A source scan that resolves to zero files after applying its allowlist shall
    fail loudly rather than pass silently.
  priority: must
  stability: stable
- id: ancora.source_scan.whole_token_matching
  statement: >-
    A plain-string token shall match only as a whole token and shall not match
    inside a longer identifier. Regular-expression tokens shall be used
    verbatim.
  priority: must
  stability: stable
- id: ancora.source_scan.no_execution
  statement: >-
    `Ancora.SourceScan` shall read files only and shall not spawn processes, run
    shell commands, or open ports.
  priority: must
  stability: stable
```

## Scenarios

```yaml spec-scenarios
- id: ancora.source_scan.scenario.configured_scan
  given:
    - directories and globs containing planted string and regular-expression violations
    - an allowlisted file containing another violation
  when:
    - `Ancora.SourceScan.scan/1` scans the configured paths
  then:
    - it returns the non-allowlisted violations as file, line, and original-token tuples
  covers:
    - ancora.source_scan.declarative_config
- id: ancora.source_scan.scenario.empty_file_set
  given:
    - paths that resolve to no files after applying the allowlist
  when:
    - `Ancora.SourceScan.scan/1` runs
  then:
    - it raises an error that names the empty source scan
  covers:
    - ancora.source_scan.vacuity_guard
- id: ancora.source_scan.scenario.token_boundaries
  given:
    - a plain-string token inside a longer identifier and as a standalone identifier
    - a regular expression that matches both locations
  when:
    - `Ancora.SourceScan.scan/1` scans the source
  then:
    - the plain string matches only the standalone identifier and the regular expression matches verbatim
  covers:
    - ancora.source_scan.whole_token_matching
- id: ancora.source_scan.scenario.file_only
  given:
    - a source file and a configured forbidden token
  when:
    - `Ancora.SourceScan.scan/1` scans the file
  then:
    - it returns from file reads without any process, shell, or port call in its implementation
  covers:
    - ancora.source_scan.no_execution
```

## Verification

```yaml spec-verification
- kind: tagged_tests
  covers:
    - ancora.source_scan.declarative_config
    - ancora.source_scan.vacuity_guard
    - ancora.source_scan.whole_token_matching
    - ancora.source_scan.no_execution
```
