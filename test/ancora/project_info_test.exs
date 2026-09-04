Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.ProjectInfoTest do
  use Ancora.TestCase, async: false

  alias Ancora.ProjectInfo
  alias Ancora.Gate.Preflight

  @tag spec: "ancora.derive.project_info_from_root"
  test "reads literal app and elixirc paths from the target root", %{root: root} do
    write_mix(root, """
    [
      app: :sample,
      version: "0.1.0",
      elixirc_paths: ["lib", "src"]
    ]
    """)

    assert {:ok, info} = ProjectInfo.load(root)
    assert info.root == Path.expand(root)
    assert info.app == :sample
    assert info.lib_paths == ["lib", "src"]
  end

  @tag spec: "ancora.derive.project_info_from_root"
  test "dynamic elixirc paths degrade to lib", %{root: root} do
    # Would fail if ProjectInfo evaluated the target's elixirc_paths/1 call or
    # propagated its AST instead of degrading dynamic source to the default.
    write_mix(root, """
    [
      app: :sample,
      elixirc_paths: elixirc_paths(Mix.env())
    ]
    """)

    assert {:ok, info} = ProjectInfo.load(root)
    assert info.lib_paths == ["lib"]
  end

  @tag spec: "ancora.derive.project_info_from_root"
  test "reads a literal project list after a leading setup call", %{root: root} do
    # Would fail if ProjectInfo required the project list to be the only
    # expression in project/0, as the pinned Atlas control demonstrates.
    write_mix(root, """
    disable_specled_tracer_for_speed_migration()

    [
      app: :sample,
      version: get_version(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
    """)

    assert {:ok, info} = ProjectInfo.load(root)
    assert info.app == :sample
    assert info.lib_paths == ["lib"]
  end

  @tag spec: "ancora.derive.project_info_from_root"
  test "config lib_paths override dynamic elixirc paths", %{root: root} do
    write_mix(root, """
    [
      app: :sample,
      elixirc_paths: elixirc_paths(Mix.env())
    ]
    """)

    write_config(root, """
    lib_paths:
      - src
      - generated
    """)

    assert {:ok, info} = ProjectInfo.load(root)
    assert info.lib_paths == ["src", "generated"]
  end

  @tag spec: "ancora.gate.preflight_hard_fails"
  test "preflight does not read the config file again when lib_paths is absent", %{root: root} do
    init_git_repo(root)

    write_mix(root, """
    [
      app: :sample,
      elixirc_paths: ["lib", "extra"]
    ]
    """)

    write_config(root, """
    default_base: main
    """)

    write_files(root, %{".spec/specs/.keep" => ""})
    commit_all(root, "base")

    Code.ensure_loaded!(ProjectInfo)
    :erlang.trace_pattern({ProjectInfo, :configured_lib_paths, 1}, true, [:local, :call_count])

    {:call_count, calls_before} =
      :erlang.trace_info({ProjectInfo, :configured_lib_paths, 1}, :call_count)

    on_exit(fn ->
      :erlang.trace_pattern(
        {ProjectInfo, :configured_lib_paths, 1},
        false,
        [:local, :call_count]
      )
    end)

    # Would fail if preflight omitted nil lib_paths and ProjectInfo read the file again.
    assert {:ok, preflight} = Preflight.run(root, base: "HEAD")
    assert preflight.project.lib_paths == ["lib", "extra"]

    {:call_count, calls_after} =
      :erlang.trace_info({ProjectInfo, :configured_lib_paths, 1}, :call_count)

    assert calls_after - calls_before == 0
  end

  @tag spec: "ancora.derive.project_info_from_root"
  test "apps_path marks an unsupported umbrella root", %{root: root} do
    # Would fail if preflight had no source-derived umbrella signal and tried
    # to continue into an unsupported root.
    write_mix(root, """
    [
      app: :umbrella,
      apps_path: "apps"
    ]
    """)

    assert {:env, message} = ProjectInfo.load(root)
    assert message =~ "umbrella roots are not supported"
  end

  @tag spec: "ancora.derive.project_info_from_root"
  test "non-literal app fails with a useful env error", %{root: root} do
    write_mix(root, """
    [
      app: app_name(),
      elixirc_paths: ["lib"]
    ]
    """)

    assert {:env, message} = ProjectInfo.load(root)
    assert message =~ "app: as a literal atom"
    assert message =~ "dynamic app values are unsupported"
  end

  defp write_mix(root, project_body) do
    write_files(root, %{
      "mix.exs" => """
      defmodule Sample.MixProject do
        use Mix.Project

        def project do
          #{project_body}
        end
      end
      """
    })
  end
end
