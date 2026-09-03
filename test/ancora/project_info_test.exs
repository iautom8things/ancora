Code.require_file("../support/ancora_case.exs", __DIR__)

defmodule Ancora.ProjectInfoTest do
  use Ancora.TestCase

  alias Ancora.ProjectInfo

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

  @tag spec: "ancora.derive.project_info_from_root"
  test "normalizes trailing slashes from every lib_paths source", %{root: root} do
    # Would fail if any ProjectInfo resolution path returned a trailing slash
    # for downstream path comparisons to interpret independently.
    write_mix(root, "[app: :sample, elixirc_paths: [\"source/\"]]")

    assert {:ok, from_project} = ProjectInfo.load(root)
    assert from_project.lib_paths == ["source"]

    write_config(root, "lib_paths:\n  - configured/\n")
    assert {:ok, from_config} = ProjectInfo.load(root)
    assert from_config.lib_paths == ["configured"]

    assert {:ok, from_options} = ProjectInfo.load(root, lib_paths: ["explicit/"])
    assert from_options.lib_paths == ["explicit"]
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
