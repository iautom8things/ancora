defmodule Ancora.Config do
  @moduledoc """
  Loader and schema for `.spec/config.yml`.

  Allowed top-level keys: `default_base`, `test_paths`, `lib_paths`,
  `severities`, and `overrides`. `severities:` is one map whose keys are
  validated against `Ancora.Finding`. Unknown top-level keys and unknown
  codes in `severities:` produce `config/unknown_key`. Bad values produce
  `config/invalid_value`. Both codes are non-tunable.

  Each `overrides:` entry carries `subject`, `code`, `severity`, and a
  required non-empty `reason`. An override applies only to findings of
  that code attributed to that subject. An entry naming an unknown subject
  or code, or missing `reason`, produces `config/invalid_value` and is
  ignored. `spec.status` labels a subject with an applied override
  `acknowledged` (see `subject_status/2`).

  Malformed YAML degrades to defaults with a `[CONFIG]` diagnostic on
  stderr and nothing on stdout.

  `ANCORA_SHOW_INFO` is the only environment variable this module reads.

  `.spec/config.yml` and the ancora version in `mix.lock` travel together
  in git. A new finding code is configured in the same PR that bumps the
  dependency — they are co-versioned, never advertised as independently
  forward-compatible.
  """

  alias Ancora.{Finding, Output}
  alias Ancora.Severity

  defmodule Override do
    @moduledoc false
    defstruct [:subject, :code, :severity, :reason]

    @type t :: %__MODULE__{
            subject: String.t(),
            code: String.t(),
            severity: Severity.severity(),
            reason: String.t()
          }
  end

  @config_file Path.join([".spec", "config.yml"])
  @known_keys MapSet.new(["default_base", "test_paths", "lib_paths", "severities", "overrides"])

  @severity_tokens %{
    "off" => :off,
    "info" => :info,
    "warning" => :warning,
    "error" => :error
  }

  defstruct default_base: "origin/main",
            test_paths: ["test"],
            lib_paths: nil,
            severities: %{},
            overrides: [],
            findings: []

  @type t :: %__MODULE__{
          default_base: String.t(),
          test_paths: [String.t()],
          lib_paths: [String.t()] | nil,
          severities: %{optional(String.t()) => Severity.severity()},
          overrides: [Override.t()],
          findings: [Finding.t()]
        }

  @doc "Default configuration with no findings."
  @spec defaults() :: t()
  def defaults, do: %__MODULE__{}

  @doc """
  True when `ANCORA_SHOW_INFO=1`. This is the only environment variable
  ancora reads.
  """
  @spec show_info?() :: boolean()
  def show_info? do
    System.get_env("ANCORA_SHOW_INFO") == "1"
  end

  @doc """
  Loads `.spec/config.yml` relative to `root`.

  Options:

    * `:path` — override the config file path
    * `:known_subjects` — enumerable of subject ids; when given, an
      override naming a subject not in the set fires `config/invalid_value`
      and is ignored. When omitted, subject existence is not checked
      (the gate supplies the corpus once the index exists).
  """
  @spec load(String.t(), keyword()) :: t()
  def load(root, opts \\ []) when is_binary(root) do
    path = opts[:path] || Path.join(root, @config_file)
    known_subjects = opts[:known_subjects]

    case read_file(path) do
      :missing ->
        defaults()

      {:ok, ""} ->
        defaults()

      {:ok, contents} ->
        parse(contents, path: relative_path(root, path), known_subjects: known_subjects)

      {:error, reason} ->
        emit_config("could not read #{path}: #{inspect(reason)}; using defaults")
        defaults()
    end
  end

  @doc false
  @spec parse(binary(), keyword()) :: t()
  def parse(contents, opts \\ []) when is_binary(contents) do
    file = Keyword.get(opts, :path, @config_file)
    known_subjects = Keyword.get(opts, :known_subjects)

    case YamlElixir.read_from_string(contents) do
      {:ok, nil} ->
        defaults()

      {:ok, map} when is_map(map) ->
        build(map, file, known_subjects)

      {:ok, _other} ->
        emit_config("#{file} root must be a mapping; using defaults")
        defaults()

      {:error, error} ->
        emit_config("#{file} is not valid YAML (#{format_yaml_error(error)}); using defaults")
        defaults()
    end
  end

  @doc """
  Config-layer severity for `code` attributed to `subject`.

  A matching applied override wins over the `severities:` map. Returns
  `nil` when neither names the code.
  """
  @spec severity_for(t(), String.t(), String.t() | nil) :: Severity.severity() | nil
  def severity_for(%__MODULE__{} = config, code, subject) when is_binary(code) do
    case override_for(config, code, subject) do
      %Override{severity: severity} -> severity
      nil -> Map.get(config.severities, code)
    end
  end

  @doc """
  `:acknowledged` when `subject` has at least one applied override,
  otherwise `nil`. Consumed by `spec.status`.
  """
  @spec subject_status(t(), String.t()) :: :acknowledged | nil
  def subject_status(%__MODULE__{overrides: overrides}, subject) when is_binary(subject) do
    if Enum.any?(overrides, &(&1.subject == subject)), do: :acknowledged, else: nil
  end

  defp override_for(_config, _code, nil), do: nil

  defp override_for(%__MODULE__{overrides: overrides}, code, subject) do
    Enum.find(overrides, fn %Override{} = ovr ->
      ovr.subject == subject and ovr.code == code
    end)
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, :enoent} -> :missing
      {:error, reason} -> {:error, reason}
    end
  end

  defp relative_path(root, path) do
    case Path.relative_to(path, root) do
      ^path -> @config_file
      rel -> rel
    end
  end

  defp build(map, file, known_subjects) do
    findings = unknown_key_findings(map, file)

    {default_base, findings} = parse_default_base(map, file, findings)
    {test_paths, findings} = parse_string_list(map, "test_paths", ["test"], file, findings)
    {lib_paths, findings} = parse_lib_paths(map, file, findings)
    {severities, findings} = parse_severities(map, file, findings)
    {overrides, findings} = parse_overrides(map, file, known_subjects, findings)

    %__MODULE__{
      default_base: default_base,
      test_paths: test_paths,
      lib_paths: lib_paths,
      severities: severities,
      overrides: overrides,
      findings: Enum.reverse(findings)
    }
  end

  defp parse_lib_paths(map, file, findings) do
    if Map.has_key?(map, "lib_paths") do
      parse_string_list(map, "lib_paths", ["lib"], file, findings)
    else
      {nil, findings}
    end
  end

  defp unknown_key_findings(map, file) do
    map
    |> Map.keys()
    |> Enum.filter(&(is_binary(&1) and not MapSet.member?(@known_keys, &1)))
    |> Enum.map(fn key ->
      finding("config/unknown_key", file, key, "unknown top-level key #{key}")
    end)
  end

  defp parse_default_base(map, file, findings) do
    case Map.get(map, "default_base") do
      nil ->
        {"origin/main", findings}

      value when is_binary(value) and value != "" ->
        {value, findings}

      value ->
        {"origin/main",
         [
           finding(
             "config/invalid_value",
             file,
             "default_base",
             "default_base must be a non-empty string, got #{inspect(value)}"
           )
           | findings
         ]}
    end
  end

  defp parse_string_list(map, key, default, file, findings) do
    case Map.get(map, key) do
      nil ->
        {default, findings}

      list when is_list(list) ->
        strings = Enum.filter(list, &is_binary/1)

        cond do
          strings == [] ->
            {default,
             [
               finding(
                 "config/invalid_value",
                 file,
                 key,
                 "#{key} must be a list of strings"
               )
               | findings
             ]}

          length(strings) != length(list) ->
            {strings,
             [
               finding(
                 "config/invalid_value",
                 file,
                 key,
                 "#{key} entries must be strings; non-strings dropped"
               )
               | findings
             ]}

          true ->
            {strings, findings}
        end

      value ->
        {default,
         [
           finding(
             "config/invalid_value",
             file,
             key,
             "#{key} must be a list of strings, got #{inspect(value)}"
           )
           | findings
         ]}
    end
  end

  defp parse_severities(map, file, findings) do
    case Map.get(map, "severities", %{}) do
      nil ->
        {%{}, findings}

      severities when is_map(severities) ->
        Enum.reduce(severities, {%{}, findings}, fn {code, token}, {acc, diags} ->
          reduce_severity_entry(code, token, file, acc, diags)
        end)

      value ->
        {%{},
         [
           finding(
             "config/invalid_value",
             file,
             "severities",
             "severities must be a map, got #{inspect(value)}"
           )
           | findings
         ]}
    end
  end

  defp reduce_severity_entry(code, token, file, acc, diags) when is_binary(code) do
    cond do
      not Finding.known?(code) ->
        {acc,
         [
           finding(
             "config/unknown_key",
             file,
             code,
             "unknown finding code #{code} in severities:"
           )
           | diags
         ]}

      match?({:ok, _}, decode_severity(token)) ->
        {:ok, severity} = decode_severity(token)
        {Map.put(acc, code, severity), diags}

      true ->
        {acc,
         [
           finding(
             "config/invalid_value",
             file,
             code,
             "severities.#{code} must be one of off/info/warning/error, got #{inspect(token)}"
           )
           | diags
         ]}
    end
  end

  defp reduce_severity_entry(code, _token, file, acc, diags) do
    {acc,
     [
       finding(
         "config/invalid_value",
         file,
         "severities",
         "severities key must be a string finding code, got #{inspect(code)}"
       )
       | diags
     ]}
  end

  defp parse_overrides(map, file, known_subjects, findings) do
    known_subjects = known_subject_set(known_subjects)

    case Map.get(map, "overrides") do
      nil ->
        {[], findings}

      list when is_list(list) ->
        Enum.reduce(list, {[], findings}, fn entry, {applied, diags} ->
          case parse_override_entry(entry, file, known_subjects) do
            {:ok, override} -> {[override | applied], diags}
            {:error, finding} -> {applied, [finding | diags]}
          end
        end)
        |> then(fn {applied, diags} -> {Enum.reverse(applied), diags} end)

      value ->
        {[],
         [
           finding(
             "config/invalid_value",
             file,
             "overrides",
             "overrides must be a list, got #{inspect(value)}"
           )
           | findings
         ]}
    end
  end

  defp parse_override_entry(entry, file, known_subjects) when is_map(entry) do
    subject = Map.get(entry, "subject")
    code = Map.get(entry, "code")
    reason = Map.get(entry, "reason")
    token = Map.get(entry, "severity")

    cond do
      not is_binary(subject) or subject == "" ->
        {:error,
         finding(
           "config/invalid_value",
           file,
           "overrides",
           "overrides entry missing subject: #{inspect(entry)}"
         )}

      not is_binary(code) or code == "" ->
        {:error,
         finding(
           "config/invalid_value",
           file,
           "overrides",
           "overrides entry for #{subject} missing code"
         )}

      not Finding.known?(code) ->
        {:error,
         finding(
           "config/invalid_value",
           file,
           code,
           "overrides entry for #{subject} names unknown code #{code}"
         )}

      not valid_reason?(reason) ->
        {:error,
         finding(
           "config/invalid_value",
           file,
           code,
           "overrides entry for #{subject} #{code} missing reason"
         )}

      unknown_subject?(subject, known_subjects) ->
        {:error,
         finding(
           "config/invalid_value",
           file,
           subject,
           "overrides entry names unknown subject #{subject}"
         )}

      match?({:ok, _}, decode_severity(token)) ->
        {:ok, severity} = decode_severity(token)

        {:ok,
         %Override{
           subject: subject,
           code: code,
           severity: severity,
           reason: String.trim(reason)
         }}

      true ->
        {:error,
         finding(
           "config/invalid_value",
           file,
           code,
           "overrides entry for #{subject} #{code} has invalid severity #{inspect(token)}"
         )}
    end
  end

  defp parse_override_entry(entry, file, _known_subjects) do
    {:error,
     finding(
       "config/invalid_value",
       file,
       "overrides",
       "overrides entry must be a mapping, got #{inspect(entry)}"
     )}
  end

  defp valid_reason?(reason) when is_binary(reason), do: String.trim(reason) != ""
  defp valid_reason?(_), do: false

  defp known_subject_set(nil), do: nil
  defp known_subject_set(%MapSet{} = set), do: set
  defp known_subject_set(known), do: MapSet.new(known)

  defp unknown_subject?(_subject, nil), do: false
  defp unknown_subject?(subject, %MapSet{} = known), do: not MapSet.member?(known, subject)

  # YAML 1.1 parses unquoted `off`/`no`/`false` as boolean false.
  defp decode_severity(false), do: {:ok, :off}
  defp decode_severity(token) when is_binary(token), do: Map.fetch(@severity_tokens, token)
  defp decode_severity(token) when token in [:off, :info, :warning, :error], do: {:ok, token}
  defp decode_severity(_), do: :error

  defp finding(code, file, key, detail) do
    Finding.new(
      code: code,
      file: file,
      key: key,
      detail: detail,
      severity: Finding.default_severity(code),
      severity_source: :default
    )
  end

  defp emit_config(message) do
    Output.config_diagnostic(message)
  end

  defp format_yaml_error(error) when is_binary(error), do: error
  defp format_yaml_error(error) when is_exception(error), do: Exception.message(error)
  defp format_yaml_error(%{message: message}) when is_binary(message), do: message
  defp format_yaml_error(error), do: inspect(error)
end
