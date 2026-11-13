Code.require_file("../../support/ancora_case.exs", __DIR__)

defmodule Ancora.Review.GateCacheTest do
  use Ancora.TestCase

  alias Ancora.Gate.Preflight
  alias Ancora.Review
  alias Ancora.Review.GateCache

  @tag spec: "ancora.review.reuses_check_result"
  test "review builds the same view with the handoff absent, warm, truncated or garbage", %{
    root: root
  } do
    write_drifted_project(root, "/_build/\n")
    cache = Path.join(root, GateCache.path())

    assert {:ok, cold} = Review.build(root, base: "HEAD")
    refute File.exists?(cache)

    assert {:ok, _report} = Ancora.check(root, base: "HEAD", review_cache: true)
    assert File.exists?(cache)
    assert {:ok, warm} = Review.build(root, base: "HEAD")
    assert comparable(warm) == comparable(cold)

    binary = File.read!(cache)
    File.write!(cache, binary_part(binary, 0, div(byte_size(binary), 2)))
    assert {:ok, truncated} = Review.build(root, base: "HEAD")
    assert comparable(truncated) == comparable(cold)

    File.write!(cache, "not a term")
    assert {:ok, garbage} = Review.build(root, base: "HEAD")
    assert comparable(garbage) == comparable(cold)
  end

  @tag spec: "ancora.review.reuses_check_result"
  test "review reads the stored fields when the key matches", %{root: root} do
    write_drifted_project(root, "/_build/\n")
    assert {:ok, _report} = Ancora.check(root, base: "HEAD", review_cache: true)
    assert {:ok, computed} = Review.build(root, base: "HEAD")
    assert computed.meta.findings > 0

    doctor_cache(root, &%{&1 | all_findings: []})

    assert {:ok, doctored} = Review.build(root, base: "HEAD")
    assert doctored.meta.findings == 0
  end

  @tag spec: "ancora.review.reuses_check_result"
  test "every gate input moves the key and build output does not", %{root: root} do
    write_drifted_project(root, "/_build/\ntest/scratch_*\n")

    key = fn ->
      {:ok, preflight} = Preflight.run(root, base: "HEAD")
      GateCache.key(preflight)
    end

    {:ok, start} = key.()
    assert key.() == {:ok, start}

    write_files(root, %{"_build/test/lib/fixture.beam" => "x", GateCache.path() => "x"})
    assert key.() == {:ok, start}

    keys =
      Enum.map(
        [
          fn -> write_files(root, %{"lib/billing.ex" => "defmodule Billing do\nend\n"}) end,
          fn -> write_files(root, %{"lib/extra.ex" => "defmodule Extra do\nend\n"}) end,
          fn -> write_files(root, %{"test/scratch_test.exs" => "# ignored\n"}) end,
          fn -> git!(root, ["commit", "--allow-empty", "-m", "move head"]) end
        ],
        fn mutate ->
          mutate.()
          {:ok, moved} = key.()
          moved
        end
      )

    assert Enum.uniq([start | keys]) == [start | keys]
  end

  @tag spec: "ancora.review.reuses_check_result"
  @tag spec: "ancora.gate.no_derived_state"
  test "nothing is stored when the tree moves during the run or git tracks _build", %{
    root: root
  } do
    write_drifted_project(root, "/_build/\n")
    {:ok, preflight} = Preflight.run(root, base: "HEAD")
    key = GateCache.key(preflight)
    write_files(root, %{"lib/extra.ex" => "defmodule Extra do\nend\n"})

    assert :ok =
             GateCache.store(preflight, key, %{all_findings: [], checked: %{}, review_data: %{}})

    refute File.exists?(Path.join(root, GateCache.path()))

    write_files(root, %{".gitignore" => "!/_build/\n"})
    commit_all(root, "track build")

    assert {:ok, _report} = Ancora.check(root, base: "HEAD", review_cache: true)
    refute File.exists?(Path.join(root, GateCache.path()))
    assert git!(root, ["status", "--porcelain"]) == ""
  end

  @tag spec: "ancora.review.reuses_check_result"
  test "the check report is unchanged by the handoff", %{root: root} do
    write_drifted_project(root, "/_build/\n")

    for opts <- [[base: "HEAD"], [base: "HEAD", json: true]] do
      assert Ancora.check(root, [{:review_cache, true} | opts]) == Ancora.check(root, opts)
    end
  end

  @tag spec: "ancora.review.reuses_check_result"
  @tag spec: "ancora.gate.no_derived_state"
  test "spec.check writes the handoff and never reads it", %{root: root} do
    write_drifted_project(root, "/_build/\n")
    args = ["spec.check", "--root", root, "--base", "HEAD"]

    _warmup = run_mix_subprocess(args)
    assert File.exists?(Path.join(root, GateCache.path()))
    warm = run_mix_subprocess(args)
    assert warm.status == 1, warm.stdout <> warm.stderr

    doctor_cache(root, &%{&1 | all_findings: [], checked: %{}})
    stale = run_mix_subprocess(args)

    File.write!(Path.join(root, GateCache.path()), "corrupt")
    corrupt = run_mix_subprocess(args)

    for run <- [stale, corrupt] do
      assert {run.status, run.stdout} == {warm.status, warm.stdout}
    end
  end

  defp comparable(view), do: put_in(view.meta.generated_at, nil)

  defp doctor_cache(root, fun) do
    cache = Path.join(root, GateCache.path())
    {GateCache, format, key, payload} = cache |> File.read!() |> :erlang.binary_to_term()
    File.write!(cache, :erlang.term_to_binary({GateCache, format, key, fun.(payload)}))
  end

  defp write_drifted_project(root, gitignore) do
    init_git_repo(root)

    write_files(root, %{
      ".gitignore" => gitignore,
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        def project, do: [app: :fixture]
      end
      """,
      ".spec/specs/billing.spec.md" => """
      # Billing

      ```yaml spec-meta
      id: billing
      kind: module
      status: draft
      summary: Billing behavior.
      ```

      ```yaml spec-requirements
      - id: billing.next
        statement: Billing shall return the next value.
        priority: must
      ```

      ```yaml spec-scenarios
      []
      ```

      ```yaml spec-verification
      - kind: tagged_tests
        covers:
          - billing.next
      ```
      """,
      "lib/billing.ex" => "defmodule Billing do\n  def next(value), do: value\nend\n",
      "test/billing_test.exs" => """
      defmodule BillingTest do
        use ExUnit.Case
        @tag spec: "billing.next"
        test "next" do
          assert Billing.next(1) in [1, 2]
        end
      end
      """
    })

    commit_all(root, "base")

    write_files(root, %{
      "lib/billing.ex" => "defmodule Billing do\n  def next(value), do: value + 1\nend\n"
    })
  end
end
