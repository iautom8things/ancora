# Project core

Describe one coherent part of the project here.

```yaml spec-meta
id: project.core
kind: module
status: draft
summary: The project's first anchored subject.
```

## Requirements

```yaml spec-requirements
- id: project.core.works
  statement: The project core shall perform its documented operation.
  priority: must
  stability: evolving
```

## Scenarios

```yaml spec-scenarios
- id: project.core.scenario.operation
  given:
    - a valid input
  when:
    - the project core runs
  then:
    - it returns the documented result
  covers:
    - project.core.works
```

## Verification

```yaml spec-verification
- kind: tagged_tests
  covers:
    - project.core.works
```
