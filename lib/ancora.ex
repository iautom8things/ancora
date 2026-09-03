defmodule Ancora do
  @moduledoc """
  Spec-anchored traceability and drift detection for Elixir.

  The semver-stable library API is `check/2`, `validate/2`,
  `Ancora.Parser.parse_file/2`, and `Ancora.DecisionParser.parse_file/2`.
  Other callable modules and functions are internal.
  """

  alias Ancora.Gate
  alias Ancora.Config
  alias Ancora.Index
  alias Ancora.Overlap
  alias Ancora.Severity
  alias Ancora.TagFindings
  alias Ancora.TagScanner
  alias Ancora.Verifier

  @doc false
  @spec index(String.t(), keyword()) :: map()
  def index(root \\ File.cwd!(), opts \\ []) when is_binary(root) and is_list(opts) do
    Index.build(root, opts)
  end

  @doc "Runs the assembled diff gate. This function is semver-stable."
  @spec check(String.t(), keyword()) :: {:ok, map()} | {:env, String.t()}
  def check(root \\ File.cwd!(), opts \\ []) when is_binary(root) and is_list(opts) do
    Gate.check(root, opts)
  end

  @doc "Validates the current corpus without diff analysis or target compilation. This function is semver-stable."
  @spec validate(String.t(), keyword()) :: {:ok, map()}
  def validate(root \\ File.cwd!(), opts \\ []) when is_binary(root) and is_list(opts) do
    root = Path.expand(root)
    config = Config.load(root)
    index_opts = if opts[:spec_dir], do: [spec_dir: opts[:spec_dir]], else: []
    index = Index.build(root, index_opts)
    test_paths = Enum.map(config.test_paths, &Path.join(root, &1))
    {:ok, tag_map, parse_errors, dynamics} = TagScanner.scan(test_paths)

    findings =
      config.findings ++
        index["findings"] ++
        Verifier.verify(index) ++
        Overlap.analyze(index["subjects"]) ++
        TagFindings.findings(index, tag_map, parse_errors, dynamics)

    summary = Severity.summarize(findings, config: config, verbose: opts[:verbose] == true)
    strict? = opts[:strict] == true
    fail? = summary.errors > 0 or (strict? and summary.warnings > 0)

    {:ok,
     %{
       findings: summary.visible,
       checked: %{
         subjects: length(index["subjects"]),
         requirements: index["summary"]["requirements"],
         errors: summary.errors,
         warnings: summary.warnings
       },
       errors: summary.errors,
       warnings: summary.warnings,
       tier: :validate,
       fail: fail?,
       pass: not fail?
     }}
  end
end
