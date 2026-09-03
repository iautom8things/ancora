Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.ConfigTest do
  use Ancora.TestCase, async: false

  alias Ancora.Config
  alias Ancora.Finding
  alias Ancora.Severity

  describe "schema" do
    @tag spec: "ancora.findings.config_schema"
    test "loads defaults when the file is missing", %{root: root} do
      config = Config.load(root)
      assert config.default_base == "origin/main"
      assert config.test_paths == ["test"]
      assert config.lib_paths == nil
      assert config.severities == %{}
      assert config.overrides == []
      assert config.findings == []
    end

    @tag spec: "ancora.findings.config_schema"
    test "accepts the five allowed keys", %{root: root} do
      write_config(root, """
      default_base: origin/develop
      test_paths:
        - test
        - apps/web/test
      lib_paths:
        - lib
        - apps/web/lib
      severities:
        derived/drift: warning
      overrides:
        - subject: atlas.web.sessions
          code: derived/unanchored_subject
          severity: info
          reason: integration-only
      """)

      config = Config.load(root, known_subjects: ["atlas.web.sessions"])
      assert config.default_base == "origin/develop"
      assert config.test_paths == ["test", "apps/web/test"]
      assert config.lib_paths == ["lib", "apps/web/lib"]
      assert config.severities["derived/drift"] == :warning
      assert [%Config.Override{} = ovr] = config.overrides
      assert ovr.subject == "atlas.web.sessions"
      assert ovr.requirement == nil
      assert ovr.code == "derived/unanchored_subject"
      assert ovr.severity == :info
      assert ovr.reason == "integration-only"
      assert config.findings == []
    end

    @tag spec: "ancora.findings.config_schema"
    test "YAML off is decoded as :off", %{root: root} do
      write_config(root, """
      severities:
        derived/growth: off
      """)

      config = Config.load(root)
      assert config.severities["derived/growth"] == :off
    end

    @tag spec: "ancora.findings.config_schema"
    test "unknown top-level key fires config/unknown_key naming it", %{root: root} do
      write_config(root, """
      test_tags:
        enabled: true
      """)

      config = Config.load(root)

      assert Enum.any?(config.findings, fn f ->
               f.code == "config/unknown_key" and f.message =~ "test_tags"
             end)
    end

    @tag spec: "ancora.findings.config_schema"
    test "setting config/unknown_key: off in the same file does not silence it", %{root: root} do
      write_config(root, """
      test_tags:
        enabled: true
      severities:
        config/unknown_key: off
      """)

      config = Config.load(root)
      unknown = Enum.filter(config.findings, &(&1.code == "config/unknown_key"))
      assert unknown != []

      resolved = Severity.resolve_all(unknown, config: config)
      assert length(resolved) == length(unknown)
      assert Enum.all?(resolved, &(&1.severity == :warning))
      assert Enum.all?(resolved, &(&1.severity_source == :default))
    end

    @tag spec: "ancora.findings.config_schema"
    test "unknown code in severities fires config/unknown_key naming the code", %{root: root} do
      write_config(root, """
      severities:
        branch_guard_unmapped_change: warning
      """)

      config = Config.load(root)

      assert Enum.any?(config.findings, fn f ->
               f.code == "config/unknown_key" and f.message =~ "branch_guard_unmapped_change"
             end)

      refute Map.has_key?(config.severities, "branch_guard_unmapped_change")
    end

    @tag spec: "ancora.findings.config_schema"
    test "a bad severity value fires config/invalid_value", %{root: root} do
      write_config(root, """
      severities:
        derived/drift: shout
      """)

      config = Config.load(root)

      assert Enum.any?(config.findings, fn f ->
               f.code == "config/invalid_value" and f.message =~ "derived/drift"
             end)

      refute Map.has_key?(config.severities, "derived/drift")
    end

    @tag spec: "ancora.findings.config_schema"
    test "malformed YAML degrades to defaults with [CONFIG] on stderr only", %{root: root} do
      write_config(root, ": this is not: [[[[ yaml")

      {config, stderr} =
        capture_io(:stderr, fn ->
          stdout =
            capture_io(fn ->
              send(self(), {:config, Config.load(root)})
            end)

          assert stdout == ""
        end)
        |> then(fn stderr ->
          assert_received {:config, config}
          {config, stderr}
        end)

      assert config.default_base == "origin/main"
      assert config.severities == %{}
      assert config.findings == []
      assert stderr =~ "[CONFIG]"
      refute stderr == ""
    end

    @tag spec: "ancora.findings.config_schema"
    test "ANCORA_SHOW_INFO is the only environment variable the module reads" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Config)
      assert moduledoc =~ "ANCORA_SHOW_INFO"
      assert moduledoc =~ "only environment variable"
    end
  end

  describe "per-subject overrides" do
    @tag spec: "ancora.findings.per_subject_overrides"
    test "missing reason fires config/invalid_value and the override is not applied", %{
      root: root
    } do
      write_config(root, """
      overrides:
        - subject: atlas.web.sessions
          code: derived/unanchored_subject
          severity: info
      """)

      config = Config.load(root, known_subjects: ["atlas.web.sessions"])
      assert config.overrides == []

      assert Enum.any?(config.findings, fn f ->
               f.code == "config/invalid_value" and f.message =~ "atlas.web.sessions"
             end)
    end

    @tag spec: "ancora.findings.per_subject_overrides"
    test "empty reason is rejected the same as a missing reason", %{root: root} do
      write_config(root, """
      overrides:
        - subject: atlas.web.sessions
          code: derived/unanchored_subject
          severity: info
          reason: "   "
      """)

      config = Config.load(root, known_subjects: ["atlas.web.sessions"])
      assert config.overrides == []
      assert Enum.any?(config.findings, &(&1.code == "config/invalid_value"))
    end

    @tag spec: "ancora.findings.per_subject_overrides"
    test "unknown subject or code fires config/invalid_value and is ignored", %{root: root} do
      write_config(root, """
      overrides:
        - subject: does.not.exist
          code: derived/unanchored_subject
          severity: info
          reason: nope
        - subject: atlas.web.sessions
          code: branch_guard_realization_drift
          severity: info
          reason: nope
      """)

      config = Config.load(root, known_subjects: ["atlas.web.sessions"])
      assert config.overrides == []

      messages = Enum.map(config.findings, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "does.not.exist"))
      assert Enum.any?(messages, &String.contains?(&1, "branch_guard_realization_drift"))
      assert Enum.all?(config.findings, &(&1.code == "config/invalid_value"))
    end

    @tag spec: "ancora.findings.per_subject_overrides"
    test "an override applies only to the named subject", %{root: root} do
      write_config(root, """
      overrides:
        - subject: subject.a
          code: derived/unanchored_subject
          severity: info
          reason: integration-only
      """)

      config = Config.load(root, known_subjects: ["subject.a", "subject.b"])

      a =
        Finding.new(code: "derived/unanchored_subject", subject: "subject.a")
        |> List.wrap()
        |> Severity.resolve_all(config: config)
        |> hd()

      b =
        Finding.new(code: "derived/unanchored_subject", subject: "subject.b")
        |> List.wrap()
        |> Severity.resolve_all(config: config)
        |> hd()

      assert a.severity == :info
      assert a.severity_source == :config
      assert b.severity == :warning
      assert b.severity_source == :default
      assert Config.subject_status(config, "subject.a") == :acknowledged
      assert Config.subject_status(config, "subject.b") == nil
    end

    @tag spec: "ancora.findings.per_subject_overrides"
    test "a requirement-scoped override applies only to that requirement", %{root: root} do
      write_config(root, """
      overrides:
        - subject: subject.a
          requirement: subject.a.r1
          code: tags/requirement_untagged
          severity: info
          reason: blocked until the upstream API lands
      """)

      config =
        Config.load(root,
          known_subjects: ["subject.a"],
          known_requirements: ["subject.a.r1", "subject.a.r2"]
        )

      findings = [
        Finding.new(
          code: "tags/requirement_untagged",
          subject: "subject.a",
          requirement: "subject.a.r1"
        ),
        Finding.new(
          code: "tags/requirement_untagged",
          subject: "subject.a",
          requirement: "subject.a.r2"
        ),
        Finding.new(
          code: "tags/requirement_untagged",
          subject: "subject.a"
        )
      ]

      [r1, r2, subject_only] = Severity.resolve_all(findings, config: config)

      assert r1.requirement == "subject.a.r1"
      assert r1.severity == :info
      assert r1.severity_source == :config
      assert r2.requirement == "subject.a.r2"
      assert r2.severity == :info
      assert r2.severity_source == :default
      assert subject_only.requirement == nil
      assert subject_only.severity == :info
      assert subject_only.severity_source == :default
      assert Config.subject_status(config, "subject.a") == :acknowledged
    end

    @tag spec: "ancora.findings.per_subject_overrides"
    test "an override naming an unknown requirement is ignored", %{root: root} do
      write_config(root, """
      overrides:
        - subject: subject.a
          requirement: subject.a.unknown
          code: tags/requirement_untagged
          severity: info
          reason: blocked until the upstream API lands
      """)

      config =
        Config.load(root,
          known_subjects: ["subject.a"],
          known_requirements: ["subject.a.r1"]
        )

      assert config.overrides == []

      assert Enum.any?(config.findings, fn finding ->
               finding.code == "config/invalid_value" and
                 finding.message =~ "subject.a.unknown"
             end)
    end
  end

  describe "co-versioning note" do
    @tag spec: "ancora.findings.config_coversioned_note"
    test "moduledoc mentions mix.lock and configuring a new code in the same PR" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Config)
      assert moduledoc =~ "mix.lock"
      assert moduledoc =~ "same PR"
      assert moduledoc =~ "dependency"
    end
  end
end
