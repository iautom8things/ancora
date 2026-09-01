Code.require_file("fixture.exs", __DIR__)
Code.require_file("runner.exs", __DIR__)

alias AncoraReplay.Case
alias AncoraReplay.Fixture
alias AncoraReplay.Json
alias AncoraReplay.Result
alias AncoraReplay.Runner

fixture = Fixture.build!()
ancora_root = Path.expand("../..", __DIR__)

try do
  drift_case =
    struct(Case, %{
      name: "self-test-drift",
      repo: "fixture",
      sha: fixture.drift,
      kind: :drift,
      functions: ["ReplayFixture.Calculator.add/2"]
    })

  format_as_drift_case =
    struct(Case, %{
      name: "self-test-format-as-drift",
      repo: "fixture",
      sha: fixture.format,
      kind: :drift,
      functions: ["ReplayFixture.Calculator.add/2"]
    })

  drift = Runner.run(ancora_root, fixture.root, drift_case)
  format = Runner.run(ancora_root, fixture.root, format_as_drift_case)
  parse = Json.parse("not json\nspec.check result=pass\n")

  unless Result.exit_code([drift]) == 0 and Result.exit_code([format]) == 1 and
           Result.exit_code([{:error, inspect(parse)}]) == 2 do
    raise "self-test failed: drift=#{inspect(drift)} format=#{inspect(format)} parse=#{inspect(parse)}"
  end

  IO.puts("self-test drift=0 format-as-drift=1 unparseable=2")
after
  File.rm_rf(fixture.root)
end
