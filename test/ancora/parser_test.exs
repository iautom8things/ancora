Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.ParserTest do
  use Ancora.TestCase

  alias Ancora.Finding
  alias Ancora.Parser
  alias Ancora.Schema.{Exception, Meta, Requirement, Scenario, Verification}

  @specled_017 """
  # Example Subject

  ```yaml spec-meta
  id: example.subject
  kind: module
  status: active
  summary: Example summary
  ```

  ```yaml spec-requirements
  - id: example.subject.alpha
    statement: Alpha shall hold.
    priority: must
    stability: stable
  - id: example.subject.beta
    statement: Beta shall hold.
    priority: must
    stability: stable
  - id: example.subject.gamma
    statement: Gamma should hold.
    priority: should
    stability: evolving
  ```

  ```yaml spec-scenarios
  - id: example.subject.scenario.first
    covers:
      - example.subject.alpha
    given:
      - a precondition
    when:
      - an action occurs
    then:
      - the outcome is observed
  - id: example.subject.scenario.second
    covers:
      - example.subject.beta
    given:
      - another precondition
    when:
      - another action occurs
    then:
      - another outcome is observed
  ```

  ```yaml spec-verification
  - kind: tagged_tests
    covers:
      - example.subject.alpha
      - example.subject.beta
      - example.subject.gamma
  ```
  """

  describe "block grammar" do
    @tag spec: "ancora.parsing.block_grammar_unchanged"
    test "specled_ex 0.17 spec parses to the same subject, requirement, and scenario ids", %{
      root: root
    } do
      path = write_spec(root, "example", @specled_017)
      spec = Parser.parse_file(path, root)

      assert spec["title"] == "Example Subject"
      assert %Meta{id: "example.subject"} = spec["meta"]

      assert Enum.map(spec["requirements"], & &1.id) == [
               "example.subject.alpha",
               "example.subject.beta",
               "example.subject.gamma"
             ]

      assert Enum.map(spec["scenarios"], & &1.id) == [
               "example.subject.scenario.first",
               "example.subject.scenario.second"
             ]

      assert spec["parse_errors"] == []
      refute Enum.any?(spec["findings"], &(&1.code == "spec/parse_error"))
    end

    @tag spec: "ancora.parsing.block_grammar_unchanged"
    test "language-first, tag-first, and bare fences parse the same ids", %{root: root} do
      for {name, fence} <- [
            {"lang_first", "yaml spec-meta"},
            {"tag_first", "spec-meta yaml"},
            {"bare", "spec-meta"}
          ] do
        path =
          write_spec(root, name, """
          # #{name}

          ```#{fence}
          id: #{name}.subject
          kind: module
          status: active
          ```
          """)

        spec = Parser.parse_file(path, root)
        assert spec["meta"].id == "#{name}.subject"
        assert spec["parse_errors"] == []
      end
    end

    @tag spec: "ancora.parsing.block_grammar_unchanged"
    test "exceptions block still parses", %{root: root} do
      path =
        write_spec(root, "with_exception", """
        # With Exception

        ```spec-meta
        id: with.exception
        kind: module
        status: active
        ```

        ```spec-exceptions
        - id: with.exception.gap
          covers:
            - with.exception
          reason: accepted gap
        ```
        """)

      spec = Parser.parse_file(path, root)
      assert [%Exception{id: "with.exception.gap", reason: "accepted gap"}] = spec["exceptions"]
    end

    @tag spec: "ancora.parsing.block_grammar_unchanged"
    test "decode and duplicate-block errors are recorded without crashing", %{root: root} do
      path =
        write_spec(root, "invalid", """
        # Invalid

        ```spec-meta
        id: [
        ```

        ```spec-requirements
        id: wrong-shape
        statement: still wrong
        ```
        """)

      spec = Parser.parse_file(path, root)
      assert Enum.any?(spec["parse_errors"], &String.contains?(&1, "spec-meta decode failed"))
      assert "spec-requirements must decode to a list" in spec["parse_errors"]
      assert Enum.any?(spec["findings"], &(&1.code == "spec/parse_error"))
    end
  end

  describe "retired constructs" do
    @tag spec: "ancora.parsing.retired_constructs_tolerated"
    test "carrying and stripped copies parse to the same ids; stripped HEAD emits no retired finding",
         %{root: root} do
      carrying = """
      # Pair

      ```spec-meta
      id: pair.subject
      kind: module
      status: active
      realized_by:
        api_boundary:
          - "Pair.run/1"
      ```

      ```spec-requirements
      - id: pair.subject.req
        statement: Pair shall run.
        realized_by:
          implementation:
            - "Pair.run/1"
      ```

      ```spec-verification
      - kind: tagged_tests
        execute: true
        covers:
          - pair.subject.req
      ```
      """

      stripped = """
      # Pair

      ```spec-meta
      id: pair.subject
      kind: module
      status: active
      ```

      ```spec-requirements
      - id: pair.subject.req
        statement: Pair shall run.
      ```

      ```spec-verification
      - kind: tagged_tests
        covers:
          - pair.subject.req
      ```
      """

      carrying_path = write_spec(root, "pair_carrying", carrying)
      stripped_path = write_spec(root, "pair_stripped", stripped)

      carrying_spec = Parser.parse_file(carrying_path, root)
      stripped_spec = Parser.parse_file(stripped_path, root)

      assert carrying_spec["meta"].id == stripped_spec["meta"].id
      assert Enum.map(carrying_spec["requirements"], & &1.id) == ["pair.subject.req"]
      assert Enum.map(stripped_spec["requirements"], & &1.id) == ["pair.subject.req"]

      assert Enum.any?(carrying_spec["findings"], &(&1.code == "format/retired_construct"))

      refute Enum.any?(
               stripped_spec["findings"],
               &(&1.code == "format/retired_construct")
             )
    end

    @tag spec: "ancora.parsing.retired_constructs_tolerated"
    test "HEAD source_file plus execute: false fires format/retired_construct once", %{
      root: root
    } do
      path =
        write_spec(root, "retired_head", """
        # Retired Head

        ```spec-meta
        id: retired.head
        kind: module
        status: active
        ```

        ```spec-requirements
        - id: retired.head.req
          statement: Retired head shall parse.
        ```

        ```spec-verification
        - kind: source_file
          target: lib/retired.ex
          execute: false
          covers:
            - retired.head.req
        ```
        """)

      spec = Parser.parse_file(path, root)
      retired = Enum.filter(spec["findings"], &(&1.code == "format/retired_construct"))

      assert length(retired) == 1
      assert hd(retired).file =~ "retired_head.spec.md"

      others =
        Enum.reject(spec["findings"], &(&1.code == "format/retired_construct"))

      refute Enum.any?(others, fn finding ->
               String.contains?(finding.message, "source_file") or
                 String.contains?(to_string(finding.message), "execute")
             end)
    end

    @tag spec: "ancora.parsing.retired_constructs_tolerated"
    test "realized_by on meta, execute on a scenario, and command kind each fire retired_construct",
         %{root: root} do
      meta_path =
        write_spec(root, "rb_meta", """
        # RB Meta

        ```spec-meta
        id: rb.meta
        kind: module
        status: active
        realized_by:
          shenanigans:
            - "Foo"
        ```
        """)

      scenario_path =
        write_spec(root, "exec_scenario", """
        # Exec Scenario

        ```spec-meta
        id: exec.scenario
        kind: module
        status: active
        ```

        ```spec-scenarios
        - id: exec.scenario.s1
          covers:
            - exec.scenario
          given:
            - g
          when:
            - w
          then:
            - t
          execute: false
        ```
        """)

      command_path =
        write_spec(root, "kind_command", """
        # Kind Command

        ```spec-meta
        id: kind.command
        kind: module
        status: active
        ```

        ```spec-verification
        - kind: command
          target: mix test
          covers:
            - kind.command
        ```
        """)

      for path <- [meta_path, scenario_path, command_path] do
        spec = Parser.parse_file(path, root)
        assert spec["parse_errors"] == []
        assert Enum.any?(spec["findings"], &(&1.code == "format/retired_construct"))
      end
    end

    @tag spec: "ancora.parsing.retired_constructs_tolerated"
    test "garbage verification kind is spec/parse_error naming the file and the entry", %{
      root: root
    } do
      path =
        write_spec(root, "garbage_kind", """
        # Garbage Kind

        ```spec-meta
        id: garbage.kind
        kind: module
        status: active
        ```

        ```spec-verification
        - kind: bananas
          covers:
            - garbage.kind
        ```
        """)

      spec = Parser.parse_file(path, root)

      assert Enum.any?(spec["findings"], fn %Finding{} = finding ->
               finding.code == "spec/parse_error" and
                 finding.file =~ "garbage_kind.spec.md" and
                 finding.message =~ "bananas"
             end)

      refute Enum.any?(spec["findings"], &(&1.code == "format/retired_construct"))
    end
  end

  describe "stable public API" do
    @tag spec: "ancora.parsing.stable_public_api"
    test "parse_file/2 is exported and documented as stable" do
      assert {:module, _} = Code.ensure_loaded(Parser)
      assert function_exported?(Parser, :parse_file, 2)
      {:docs_v1, _, _, _, module_doc, _, function_docs} = Code.fetch_docs(Parser)

      moduledoc =
        case module_doc do
          %{"en" => text} -> text
          :none -> ""
        end

      assert moduledoc =~ "semver-stable"

      parse_doc =
        Enum.find_value(function_docs, fn
          {{:function, :parse_file, 2}, _, _, %{"en" => text}, _} -> text
          _ -> nil
        end)

      assert is_binary(parse_doc)
      assert parse_doc =~ "semver-stable"
      assert moduledoc =~ ~s[`"exceptions"` key]
      assert moduledoc =~ "`spec-exceptions` block are deprecated"
      assert moduledoc =~ "Ancora 2.0 will remove them"
      assert parse_doc =~ ~s[`"exceptions"` return key]
      assert parse_doc =~ "deprecated"
      assert parse_doc =~ "Ancora 2.0"
    end

    @tag spec: "ancora.parsing.stable_public_api"
    test "return shape includes the Atlas contract keys", %{root: root} do
      path = write_spec(root, "shape", @specled_017)
      spec = Parser.parse_file(path, root)

      for key <-
            ~w(exceptions file findings meta parse_errors requirements scenarios verification title) do
        assert Map.has_key?(spec, key), "missing #{key}"
      end

      assert spec["exceptions"] == []
      assert is_list(spec["findings"])
      assert [%Requirement{} | _] = spec["requirements"]
      assert [%Scenario{} | _] = spec["scenarios"]
      assert [%Verification{kind: "tagged_tests"}] = spec["verification"]
    end
  end
end
