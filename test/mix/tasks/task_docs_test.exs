defmodule Mix.Tasks.Spec.TaskDocsTest do
  use ExUnit.Case, async: true

  @tasks %{
    Mix.Tasks.Spec.Check => ~w(--base --verbose --debug --root --spec-dir --json),
    Mix.Tasks.Spec.Validate => ~w(--strict --debug --root --spec-dir),
    Mix.Tasks.Spec.Prime => ~w(--base --since --root --spec-dir),
    Mix.Tasks.Spec.Next => ~w(--base --since --verbose),
    Mix.Tasks.Spec.Status => ~w(--root --spec-dir),
    Mix.Tasks.Spec.Review => ~w(--base --output --open --root --spec-dir -o -r),
    Mix.Tasks.Spec.Init => ~w(--root --force -r -f),
    Mix.Tasks.Spec.Decision.New => ~w(DECISION_ID --root --title --force -r -f)
  }

  @spec_dir_tasks [
    Mix.Tasks.Spec.Check,
    Mix.Tasks.Spec.Validate,
    Mix.Tasks.Spec.Prime,
    Mix.Tasks.Spec.Status,
    Mix.Tasks.Spec.Review
  ]

  @tag spec: "ancora.tasks.report_task_flags"
  @tag spec: "ancora.tasks.mix_bootstrap_posture"
  test "all eight task moduledocs list every option, argument, alias, and default" do
    # Would fail if the published help omitted a task flag or its default behavior.
    for {module, options} <- @tasks do
      Code.ensure_loaded!(module)
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(module)

      assert moduledoc =~ "A cold checkout may print dependency compilation lines"
      assert moduledoc =~ "## Options"
      assert moduledoc =~ "Defaults to"

      for option <- options do
        assert moduledoc =~ "`#{option}"
      end
    end

    callable_surfaces = [
      &Mix.Tasks.Spec.Check.run/1,
      &Mix.Tasks.Spec.Validate.run/1,
      &Mix.Tasks.Spec.Prime.run/1,
      &Mix.Tasks.Spec.Next.run/1,
      &Mix.Tasks.Spec.Status.run/1,
      &Mix.Tasks.Spec.Review.run/1,
      &Mix.Tasks.Spec.Init.run/1,
      &Mix.Tasks.Spec.Decision.New.run/1
    ]

    assert Enum.all?(callable_surfaces, &is_function(&1, 1))
  end

  @tag spec: "ancora.tasks.report_task_flags"
  @tag spec: "ancora.tasks.check_flags"
  test "spec-dir help names the workspace and matches the real default" do
    # Would fail if one task documented the subject directory or a default
    # other than the workspace selected when the flag is absent.
    assert {:ok, default_spec_dir} = Ancora.Index.detect_spec_dir(File.cwd!())

    for module <- @spec_dir_tasks do
      Code.ensure_loaded!(module)
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(module)

      assert [_, documented_default] =
               Regex.run(
                 ~r/`--spec-dir DIR` selects the ancora workspace directory\. Defaults to `([^`]+)`\./,
                 moduledoc
               )

      assert documented_default == default_spec_dir
    end
  end

  @tag spec: "ancora.tasks.ci_explicit_base"
  test "CI selects an explicit base for each event" do
    # Would fail if push checks compared main against itself or PR checks lost their base ref.
    workflow = File.read!(Path.expand("../../../.github/workflows/ci.yml", __DIR__))

    assert workflow =~ "EVENT_NAME: ${{ github.event_name }}"
    assert workflow =~ "PUSH_BASE_SHA: ${{ github.event.before }}"
    assert workflow =~ ~S|[[ "$PUSH_BASE_SHA" =~ ^0+$ ]]|
    assert workflow =~ ~S|base_ref="$PUSH_BASE_SHA"|
    assert workflow =~ ~S|branch_ref="${PR_BASE_REF:-$DEFAULT_BRANCH}"|
    assert workflow =~ ~S|base_ref="origin/$branch_ref"|
    assert workflow =~ ~S|mix spec.check --base "$base_ref"|
  end
end
