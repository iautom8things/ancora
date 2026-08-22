defmodule Ancora.SeverityTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Ancora.Config
  alias Ancora.Finding
  alias Ancora.Severity

  defp finding(code, opts \\ []) do
    Finding.new(
      Keyword.merge(
        [code: code, subject: "example.subject", file: "lib/example.ex"],
        opts
      )
    )
  end

  describe "precedence matrix" do
    @tag spec: "ancora.findings.severity_precedence"
    test "registry default wins when neither config nor trailer names the code" do
      assert Severity.resolve("derived/growth", [], :warning) == :warning

      [resolved] = Severity.resolve_all([finding("derived/growth")], [])
      assert resolved.severity == :warning
      assert resolved.severity_source == :default
    end

    @tag spec: "ancora.findings.severity_precedence"
    test "config severities beat the registry default" do
      opts = [config_severities: %{"derived/growth" => :error}]
      assert Severity.resolve("derived/growth", opts, :warning) == :error

      [resolved] = Severity.resolve_all([finding("derived/growth")], opts)
      assert resolved.severity == :error
      assert resolved.severity_source == :config
    end

    @tag spec: "ancora.findings.severity_precedence"
    test "trailer downgrades config error to warning with source :trailer" do
      opts = [
        config_severities: %{"derived/drift" => :error},
        trailer_override: %{"derived/drift" => :warning}
      ]

      assert {severity, source} =
               Severity.resolve_with_source("derived/drift", opts, :error)

      assert severity == :warning
      assert source == :trailer

      [resolved] = Severity.resolve_all([finding("derived/drift")], opts)
      assert resolved.severity == :warning
      assert resolved.severity_source == :trailer
    end

    @tag spec: "ancora.findings.severity_precedence"
    test "config off absorbs a trailer and the finding is not emitted" do
      opts = [
        config_severities: %{"derived/growth" => :off},
        trailer_override: %{"derived/growth" => :warning}
      ]

      assert Severity.resolve("derived/growth", opts, :warning) == :off
      assert Severity.resolve_all([finding("derived/growth")], opts) == []
    end

    @tag spec: "ancora.findings.severity_precedence"
    test "per-subject override is config-layer and does not affect another subject" do
      config = %Config{
        overrides: [
          %Config.Override{
            subject: "subject.a",
            code: "derived/unanchored_subject",
            severity: :info,
            reason: "integration-only"
          }
        ]
      }

      a =
        finding("derived/unanchored_subject", subject: "subject.a")
        |> List.wrap()
        |> Severity.resolve_all(config: config)
        |> hd()

      b =
        finding("derived/unanchored_subject", subject: "subject.b")
        |> List.wrap()
        |> Severity.resolve_all(config: config)
        |> hd()

      assert a.severity == :info
      assert a.severity_source == :config
      assert b.severity == :warning
      assert b.severity_source == :default
    end

    @tag spec: "ancora.findings.severity_precedence"
    test "non-tunable codes ignore config off and trailers" do
      opts = [
        config_severities: %{"config/unknown_key" => :off},
        trailer_override: %{"config/unknown_key" => :info}
      ]

      assert {severity, source} =
               Severity.resolve_with_source("config/unknown_key", opts, :warning)

      assert severity == :warning
      assert source == :default

      [resolved] = Severity.resolve_all([finding("config/unknown_key")], opts)
      assert resolved.severity == :warning
      assert resolved.severity_source == :default
    end

    @tag spec: "ancora.findings.trailer_grammar"
    test "a trailer that would raise above config-resolved severity is ignored" do
      opts = [
        config_severities: %{"derived/unresolved_calls" => :info},
        trailer_override: %{"derived/unresolved_calls" => :warning}
      ]

      stderr =
        capture_io(:stderr, fn ->
          assert {severity, source} =
                   Severity.resolve_with_source(
                     "derived/unresolved_calls",
                     opts,
                     :info
                   )

          assert severity == :info
          assert source == :config
        end)

      assert stderr =~ "[CONFIG]"
      assert stderr =~ "derived/unresolved_calls"
      assert stderr =~ "warning"
    end
  end

  describe "info visibility" do
    @tag spec: "ancora.findings.info_visibility"
    test "info findings are hidden by default, do not block, and increment hidden_info" do
      findings = [finding("derived/unresolved_calls"), finding("derived/drift")]

      summary = Severity.summarize(findings, show_info: false, verbose: false)

      refute Enum.any?(summary.visible, &(&1.severity == :info))
      assert summary.hidden_info == 1
      assert summary.errors == 1
      assert summary.warnings == 0
      assert summary.blocking?

      info_only = Severity.summarize([finding("derived/unresolved_calls")], show_info: false)
      assert info_only.visible == []
      assert info_only.hidden_info == 1
      assert info_only.errors == 0
      assert info_only.warnings == 0
      refute info_only.blocking?
    end

    @tag spec: "ancora.findings.info_visibility"
    test "info findings become visible with verbose but still do not block" do
      summary = Severity.summarize([finding("derived/unresolved_calls")], verbose: true)

      assert length(summary.visible) == 1
      assert hd(summary.visible).severity == :info
      assert summary.hidden_info == 0
      refute summary.blocking?
    end
  end

  describe "known severities" do
    @tag spec: "ancora.findings.severity_precedence"
    test "lists off, info, warning, and error" do
      assert Enum.sort(Severity.known_severities()) == [:error, :info, :off, :warning]
    end
  end
end

defmodule Ancora.Severity.InfoEnvTest do
  use ExUnit.Case, async: false

  alias Ancora.Config
  alias Ancora.Finding
  alias Ancora.Severity

  @tag spec: "ancora.findings.info_visibility"
  test "ANCORA_SHOW_INFO=1 makes info findings visible" do
    previous = System.get_env("ANCORA_SHOW_INFO")

    on_exit(fn ->
      if previous,
        do: System.put_env("ANCORA_SHOW_INFO", previous),
        else: System.delete_env("ANCORA_SHOW_INFO")
    end)

    System.delete_env("ANCORA_SHOW_INFO")
    refute Config.show_info?()

    System.put_env("ANCORA_SHOW_INFO", "1")
    assert Config.show_info?()

    finding =
      Finding.new(
        code: "tags/dynamic_value",
        subject: "example.subject",
        file: "test/example_test.exs"
      )

    summary = Severity.summarize([finding], verbose: false)
    assert length(summary.visible) == 1
    assert summary.hidden_info == 0
    refute summary.blocking?
  end
end
