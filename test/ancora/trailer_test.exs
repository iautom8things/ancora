Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.TrailerTest do
  use Ancora.TestCase, async: false

  alias Ancora.Finding
  alias Ancora.Severity
  alias Ancora.Trailer

  describe "parse grammar" do
    @tag spec: "ancora.findings.trailer_grammar"
    test "accepts Spec-Ack: code=info|warning for registry codes" do
      assert %{overrides: %{"derived/drift" => :warning}, warnings: []} =
               Trailer.parse("Some subject\n\nSpec-Ack: derived/drift=warning\n")

      assert %{overrides: %{"derived/growth" => :info}, warnings: []} =
               Trailer.parse("Spec-Ack: derived/growth=info")
    end

    @tag spec: "ancora.findings.trailer_grammar"
    test "body without Spec-Ack lines yields empty overrides" do
      assert %{overrides: %{}, warnings: []} = Trailer.parse("just a normal commit")
    end

    @tag spec: "ancora.findings.trailer_grammar"
    test "rejects error and off at parse, names the severity on stderr, leaves the finding" do
      stderr =
        capture_io(:stderr, fn ->
          stdout =
            capture_io(fn ->
              assert %{overrides: %{}, warnings: warnings} =
                       Trailer.parse("Spec-Ack: derived/unresolved_calls=error")

              assert warnings != []
              assert Enum.any?(warnings, &String.contains?(&1, "[CONFIG]"))
            end)

          assert stdout == ""
        end)

      assert stderr =~ "[CONFIG]"
      assert stderr =~ "derived/unresolved_calls=error"

      finding =
        Finding.new(
          code: "derived/unresolved_calls",
          subject: "example.subject",
          file: "test/example_test.exs"
        )

      [resolved] =
        Severity.resolve_all([finding], trailer_override: %{})

      assert resolved.severity == :info
      assert resolved.severity_source == :default
    end

    @tag spec: "ancora.findings.trailer_grammar"
    test "unknown trailer code warns on stderr and changes no severity" do
      stderr =
        capture_io(:stderr, fn ->
          stdout =
            capture_io(fn ->
              assert %{overrides: %{}, warnings: warnings} =
                       Trailer.parse("Spec-Ack: branch_guard_realization_drift=info")

              assert Enum.any?(warnings, &String.contains?(&1, "branch_guard_realization_drift"))
            end)

          assert stdout == ""
        end)

      assert stderr =~ "[CONFIG]"
      assert stderr =~ "branch_guard_realization_drift"
    end

    @tag spec: "ancora.findings.trailer_grammar"
    test "unknown severity warns and produces no override" do
      stderr =
        capture_io(:stderr, fn ->
          assert %{overrides: %{}} = Trailer.parse("Spec-Ack: derived/drift=panic")
        end)

      assert stderr =~ "[CONFIG]"
      assert stderr =~ "derived/drift=panic"
    end

    @tag spec: "ancora.findings.trailer_grammar"
    test "presets are not supported" do
      stderr =
        capture_io(:stderr, fn ->
          assert %{overrides: %{}} = Trailer.parse("Spec-Ack: refactor")
        end)

      assert stderr =~ "[CONFIG]"
      assert stderr =~ "refactor"
    end
  end

  describe "read/2 scans base..HEAD" do
    @tag spec: "ancora.findings.trailer_grammar"
    test "trailer on an earlier commit applies to the branch", %{root: root} do
      init_git_repo(root)
      write_files(root, %{"README.md" => "init\n"})
      commit_all(root, "initial")

      write_files(root, %{"file.ex" => "defmodule A do\nend\n"})
      git!(root, ["add", "."])

      git!(root, [
        "commit",
        "-m",
        """
        Mechanical format

        Spec-Ack: derived/drift=warning
        """
      ])

      write_files(root, %{"file.ex" => "defmodule A do\n  def hi, do: :hi\nend\n"})
      commit_all(root, "tip commit without trailer")

      result = Trailer.read(root, "main~2")
      assert result.overrides["derived/drift"] == :warning
      assert result.non_tip_overrides == %{"derived/drift" => :warning}

      [resolved] =
        Severity.resolve_all(
          [Finding.new(code: "derived/drift", subject: "a", file: "file.ex")],
          trailer_override: result.overrides
        )

      assert resolved.severity == :warning
      assert resolved.severity_source == :trailer
    end

    @tag spec: "ancora.findings.trailer_grammar"
    test "empty range yields empty overrides", %{root: root} do
      init_git_repo(root)
      write_files(root, %{"README.md" => "init\n"})
      commit_all(root, "initial")

      assert %{overrides: %{}, warnings: [], non_tip_overrides: %{}} =
               Trailer.read(root, "HEAD")
    end

    @tag spec: "ancora.findings.trailer_grammar"
    test "git failure returns empty result", %{root: root} do
      assert %{overrides: %{}, warnings: [], non_tip_overrides: %{}} =
               Trailer.read(root, "no-such-ref")
    end

    @tag spec: "ancora.findings.trailer_grammar"
    test "an override repeated at the tip is not non-tip-only", %{root: root} do
      init_git_repo(root)
      write_files(root, %{"README.md" => "init\n"})
      commit_all(root, "initial")
      write_files(root, %{"one" => "one\n"})
      commit_all(root, "earlier\n\nSpec-Ack: derived/drift=warning")
      write_files(root, %{"two" => "two\n"})
      commit_all(root, "tip\n\nSpec-Ack: derived/drift=info")

      result = Trailer.read(root, "main~2")

      assert result.overrides["derived/drift"] == :warning
      assert result.non_tip_overrides == %{}
    end
  end

  describe "self-report documentation" do
    @tag spec: "ancora.findings.trailer_grammar"
    test "moduledoc names the self-report property" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Trailer)
      assert moduledoc =~ "self-report"
      assert moduledoc =~ "small-team"
    end
  end
end
