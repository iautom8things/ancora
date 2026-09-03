# Spec Infrastructure

Smoke test subject confirming the specled verification tooling works in Builder.

```spec-meta
id: builder.spec_infrastructure
kind: policy
status: active
summary: The spec verification toolchain is initialized and functional
surface:
  - .spec/
  - deps/spec_led_ex/
```

```spec-requirements
- id: builder.spec_infrastructure.r1
  priority: must
  stability: stable
  statement: >
    Running mix spec.check exits 0 when all spec files are structurally valid
    and all verification targets pass.
```

```spec-scenarios
- id: builder.spec_infrastructure.s1
  covers:
    - builder.spec_infrastructure.r1
  given:
    - specled_ex is listed as a dependency in mix.exs
    - .spec/specs/ contains at least one well-formed spec file
  when:
    - mix spec.check is run
  then:
    - exits 0 with no errors
```

```spec-verification
- kind: command
  target: mix spec.validate
  covers:
    - builder.spec_infrastructure.r1
```
