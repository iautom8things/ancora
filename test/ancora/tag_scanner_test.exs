Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.TagScannerTest do
  use Ancora.TestCase

  alias Ancora.TagScanner

  describe "scan_file/1 — literal string form" do
    @tag spec: "ancora.parsing.tag_discovery"
    test "extracts a single @tag spec: id", %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          @tag spec: "auth.login"
          test "logs in" do
            assert true
          end
        end
        """)

      assert {:ok, tags} = TagScanner.scan_file(path)
      assert [%{id: "auth.login", test_name: "logs in"}] = tags
    end
  end

  describe "scan_file/1 — keyword list and list of ids" do
    @tag spec: "ancora.parsing.tag_discovery"
    test "extracts spec from a keyword list, ignoring other keys", %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          @tag [spec: "auth.logout", timeout: 5_000]
          test "logs out" do
            assert true
          end
        end
        """)

      assert {:ok, [%{id: "auth.logout", test_name: "logs out"}]} = TagScanner.scan_file(path)
    end

    @tag spec: "ancora.parsing.tag_discovery"
    test "extracts all ids from a list literal", %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          @tag spec: ["a.one", "a.two"]
          test "multi" do
            assert true
          end
        end
        """)

      assert {:ok, tags} = TagScanner.scan_file(path)
      ids = tags |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == ["a.one", "a.two"]
    end
  end

  describe "scan_file/1 — @moduletag and @describetag" do
    @tag spec: "ancora.parsing.tag_discovery"
    test "moduletag attaches to every test including those inside describe", %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          @moduletag spec: "domain.root"

          test "first" do
            assert true
          end

          describe "group" do
            test "nested" do
              assert true
            end
          end
        end
        """)

      assert {:ok, tags} = TagScanner.scan_file(path)
      names = tags |> Enum.map(& &1.test_name) |> Enum.sort()
      assert names == ["first", "nested"]
      assert Enum.all?(tags, &(&1.id == "domain.root"))
    end

    @tag spec: "ancora.parsing.tag_discovery"
    test "describetag attaches to tests in the describe block", %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          describe "group" do
            @describetag spec: "auth.group"

            test "nested" do
              assert true
            end
          end
        end
        """)

      assert {:ok, [%{id: "auth.group", test_name: "nested"}]} = TagScanner.scan_file(path)
    end
  end

  describe "scan_file/1 — for-comprehension bodies" do
    @tag spec: "ancora.parsing.tag_discovery"
    test "tag inside a for-comprehension is attributed to the subject", %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          for {name, input} <- [{"alpha", 1}, {"beta", 2}] do
            @tag spec: "ancora.parsing.tag_discovery"
            test name do
              assert true
            end
          end
        end
        """)

      assert {:ok, tags} = TagScanner.scan_file(path)

      assert Enum.any?(tags, fn tag ->
               tag.id == "ancora.parsing.tag_discovery" and tag.file == path
             end),
             "Would fail if TagScanner omitted the {:for, ...} process_statement head and skipped tags inside for-comprehension bodies"

      folded = TagScanner.fold_to_subjects(tags)

      assert Enum.any?(folded, fn tag ->
               tag.id == "ancora.parsing" and tag.file == path
             end),
             "Would fail if TagScanner did not fold requirement ids up to subject ids for the detector"
    end

    @tag spec: "ancora.parsing.tag_discovery"
    test "an interpolated generated test name is recorded as nil, a literal one verbatim",
         %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          for phase <- [:plan, :apply] do
            @tag spec: "workflow.interpolated"
            test "gates \#{phase}" do
              assert true
            end
          end

          for _phase <- [:plan, :apply] do
            @tag spec: "workflow.literal"
            test "gates every phase" do
              assert true
            end
          end
        end
        """)

      assert {:ok, tags} = TagScanner.scan_file(path)

      assert [
               %{id: "workflow.interpolated", test_name: nil},
               %{id: "workflow.literal", test_name: "gates every phase"}
             ] = Enum.sort_by(tags, & &1.test_line)
    end

    @tag spec: "ancora.parsing.tag_discovery"
    test "a @tag before a comprehension is consumed inside it, not by the test after it",
         %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          @tag spec: "workflow.phase_gating"
          for phase <- [:plan, :apply] do
            test "gates \#{phase}" do
              assert true
            end
          end

          test "unrelated" do
            assert true
          end
        end
        """)

      assert {:ok, tags} = TagScanner.scan_file(path)
      assert [%{id: "workflow.phase_gating", test_name: nil}] = tags
    end

    @tag spec: "ancora.parsing.tag_discovery"
    test "module and describe tags reach for-generated tests", %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          @moduletag spec: "domain.root"

          describe "group" do
            @describetag spec: "auth.group"

            for phase <- [:plan, :apply, :skip], phase != :skip do
              @tag spec: "auth.test"
              test "gates \#{phase}" do
                assert true
              end
            end
          end
        end
        """)

      assert {:ok, tags} = TagScanner.scan_file(path)
      ids = tags |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == ["auth.group", "auth.test", "domain.root"]
    end

    @tag spec: "ancora.parsing.tag_discovery"
    test "a trailing @tag inside the body binds the statement after the comprehension",
         %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          for phase <- [:plan, :apply] do
            test "gates \#{phase}" do
              assert true
            end

            @tag spec: "workflow.trailing"
          end

          test "after loop" do
            assert true
          end
        end
        """)

      assert {:ok, tags} = TagScanner.scan_file(path)
      assert [%{id: "workflow.trailing", test_name: "after loop"}] = tags
    end
  end

  describe "scan_file/1 — dynamic values" do
    @tag spec: "ancora.parsing.tag_discovery"
    test "non-literal tag value is recorded as dynamic and does not guess a subject", %{
      root: root
    } do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          @subject "ancora.parsing"

          @tag spec: @subject <> ".x"
          test "dynamic" do
            assert true
          end
        end
        """)

      assert {:ok, tags, dynamic} = TagScanner.scan_file(path, include_dynamic: true)

      assert tags == [],
             "Would fail if TagScanner guessed a subject from a non-literal @tag spec value"

      assert [%{file: ^path, test_name: "dynamic"}] = dynamic
    end

    @tag spec: "ancora.parsing.tag_discovery"
    test "a non-literal @tag spec inside a for-comprehension is reported as dynamic", %{
      root: root
    } do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          @module_attr "some-id"

          for phase <- [:plan, :apply] do
            @tag spec: @module_attr
            test "gates \#{phase}" do
              assert true
            end
          end
        end
        """)

      assert {:ok, tags, dynamic} = TagScanner.scan_file(path, include_dynamic: true)
      assert tags == []
      assert [%{file: ^path, test_name: nil}] = dynamic
    end
  end

  describe "scan_file/1 — ignored non-spec tags" do
    @tag spec: "ancora.parsing.tag_discovery"
    test "ignores @tag annotations without a spec key", %{root: root} do
      path =
        write_test_file(root, "test/example_test.exs", """
        defmodule ExampleTest do
          use ExUnit.Case

          @tag :slow
          test "slow" do
            assert true
          end
        end
        """)

      assert {:ok, []} = TagScanner.scan_file(path)
    end
  end

  describe "scan/2 aggregation" do
    @tag spec: "ancora.parsing.tag_discovery"
    test "aggregates tags across files and records parse errors", %{root: root} do
      write_test_file(root, "test/ok_test.exs", """
      defmodule OkTest do
        use ExUnit.Case

        @tag spec: "ok.one"
        test "works" do
          assert true
        end
      end
      """)

      broken_path = write_test_file(root, "test/broken_test.exs", "defmodule do do\n")

      assert {:ok, tag_map, parse_errors, dynamic} = TagScanner.scan([Path.join(root, "test")])

      assert Map.has_key?(tag_map, "ok.one")
      assert [%{file: ^broken_path, reason: _}] = parse_errors
      assert dynamic == []
    end
  end
end
