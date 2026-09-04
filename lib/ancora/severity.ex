defmodule Ancora.Severity do
  @moduledoc """
  Per-finding severity resolver.

  Precedence (highest to lowest), with one exception:

      config off > Spec-Ack: trailer downgrade > config severity > registry default

  `off` in config (the `severities:` map or a per-subject override) is
  absorbing: a trailer cannot re-noise a code the repo silenced. A finding
  resolved to `off` is not emitted and is not counted.

  Trailer values apply only as a downgrade: never higher than the
  config-resolved severity (the config value if present, else the registry
  default). Attempts to raise emit a `[CONFIG]` line on stderr and are
  ignored.

  `config/unknown_key` and `config/invalid_value` are non-tunable: they stay
  at the registry default regardless of config or trailer.

  Resolved findings carry `severity_source` as `:config`, `:trailer`, or
  `:default`.
  """

  alias Ancora.Config
  alias Ancora.Finding
  alias Ancora.Output

  @known [:off, :info, :warning, :error]
  @rank %{error: 3, warning: 2, info: 1, off: 0}

  @type severity :: Finding.severity()
  @type source :: Finding.source()

  @doc "Known severity atoms."
  @spec known_severities() :: [severity()]
  def known_severities, do: @known

  @doc "True when `value` is a recognized severity."
  @spec known?(term()) :: boolean()
  def known?(value), do: value in @known

  @doc """
  True when a finding at `severity` fails a strict gate.

  `error` and `warning` block; `info` and `off` never do.
  """
  @spec blocking?(severity()) :: boolean()
  def blocking?(:error), do: true
  def blocking?(:warning), do: true
  def blocking?(:info), do: false
  def blocking?(:off), do: false

  @doc """
  Whether info findings should be shown.

  When `:show_info` is passed, that value wins. Otherwise true when
  `opts[:verbose]` is true or `Ancora.Config.show_info?/0` reports
  `ANCORA_SHOW_INFO=1`.
  """
  @spec show_info?(keyword() | map()) :: boolean()
  def show_info?(opts \\ []) do
    case fetch_optional(opts, :show_info) do
      {:ok, value} ->
        truthy?(value)

      :error ->
        truthy?(fetch(opts, :verbose, false)) or Config.show_info?()
    end
  end

  @doc "Resolves severity for `code` (see `resolve_with_source/3`)."
  @spec resolve(Finding.code(), keyword() | map(), severity()) :: severity()
  def resolve(code, opts, per_code_default)
      when is_binary(code) and per_code_default in @known do
    {severity, _source} = resolve_with_source(code, opts, per_code_default)
    severity
  end

  @doc """
  Resolves severity together with the layer that supplied it.

  Options:

    * `:config` — `%Ancora.Config{}` (severities + per-subject overrides)
    * `:config_severities` — `code => severity` map, used when `:config` is absent
    * `:subject` — subject id, used to match `overrides:`
    * `:trailer_override` — `code => severity` from `Ancora.Trailer`
  """
  @spec resolve_with_source(Finding.code(), keyword() | map(), severity()) ::
          {severity(), source()}
  def resolve_with_source(code, opts, per_code_default)
      when is_binary(code) and per_code_default in @known do
    if Finding.tunable?(code) do
      resolve_tunable(code, opts, per_code_default)
    else
      {per_code_default, :default}
    end
  end

  @doc """
  Resolves each finding, drops those at `off`, and sets `severity` /
  `severity_source` on the rest.
  """
  @spec resolve_all([Finding.t()], keyword() | map()) :: [Finding.t()]
  def resolve_all(findings, opts \\ []) when is_list(findings) do
    findings
    |> Enum.map(&resolve_finding(&1, opts))
    |> Enum.reject(&(&1.severity == :off))
  end

  @doc """
  Partitions resolved findings for display.

  Info findings are omitted from `:visible` unless `show_info?/1` is true,
  and never increment `:errors` or `:warnings`. `:hidden_info` is the
  count of info findings suppressed this way. `:blocking?` is true when
  any visible finding is error or warning.
  """
  @spec summarize([Finding.t()], keyword() | map()) :: %{
          visible: [Finding.t()],
          errors: non_neg_integer(),
          warnings: non_neg_integer(),
          hidden_info: non_neg_integer(),
          blocking?: boolean()
        }
  def summarize(findings, opts \\ []) when is_list(findings) do
    resolved = resolve_all(findings, opts)
    {info, rest} = Enum.split_with(resolved, &(&1.severity == :info))
    show? = show_info?(opts)
    visible = if show?, do: resolved, else: rest
    errors = Enum.count(visible, &(&1.severity == :error))
    warnings = Enum.count(visible, &(&1.severity == :warning))

    %{
      visible: visible,
      errors: errors,
      warnings: warnings,
      hidden_info: if(show?, do: 0, else: length(info)),
      blocking?: errors + warnings > 0
    }
  end

  defp resolve_finding(%Finding{} = finding, opts) do
    default = Finding.default_severity(finding.code)
    opts = put(opts, :subject, finding.subject)
    {severity, source} = resolve_with_source(finding.code, opts, default)
    %{finding | severity: severity, severity_source: source}
  end

  defp resolve_tunable(code, opts, per_code_default) do
    config_value = config_severity(code, opts)
    trailer_value = sanitized(code, fetch(opts, :trailer_override, %{}), :trailer)
    config_or_default = config_value || per_code_default

    cond do
      config_value == :off ->
        {:off, :config}

      trailer_value in [:info, :warning] and not raise?(trailer_value, config_or_default) ->
        {trailer_value, :trailer}

      trailer_value in [:info, :warning] ->
        emit_raise(code, trailer_value, config_or_default)
        fallback_after_trailer(config_value, per_code_default)

      not is_nil(config_value) ->
        {config_value, :config}

      true ->
        {per_code_default, :default}
    end
  end

  defp fallback_after_trailer(nil, per_code_default), do: {per_code_default, :default}
  defp fallback_after_trailer(config_value, _default), do: {config_value, :config}

  defp raise?(trailer, current), do: Map.fetch!(@rank, trailer) > Map.fetch!(@rank, current)

  defp emit_raise(code, trailer, current) do
    Output.config_diagnostic(
      "Spec-Ack: #{code}=#{trailer} raises above #{current}; ignored (downgrade only)"
    )
  end

  defp config_severity(code, opts) do
    subject = fetch(opts, :subject, nil)

    case fetch(opts, :config, nil) do
      %Config{} = config ->
        Config.severity_for(config, code, subject)

      _ ->
        sanitized(code, fetch(opts, :config_severities, %{}), :config)
    end
  end

  defp sanitized(code, map, source) when is_map(map) do
    case Map.get(map, code) do
      nil ->
        nil

      value when value in @known ->
        value

      bad ->
        Output.config_diagnostic(
          "ignoring unknown severity #{inspect(bad)} for #{code} from #{source}"
        )

        nil
    end
  end

  defp sanitized(_code, _other, _source), do: nil

  defp fetch(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp fetch(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)

  defp fetch_optional(opts, key) when is_list(opts) do
    if Keyword.has_key?(opts, key), do: {:ok, Keyword.get(opts, key)}, else: :error
  end

  defp fetch_optional(opts, key) when is_map(opts) do
    case Map.fetch(opts, key) do
      {:ok, _} = ok -> ok
      :error -> :error
    end
  end

  defp put(opts, key, value) when is_list(opts), do: Keyword.put(opts, key, value)
  defp put(opts, key, value) when is_map(opts), do: Map.put(opts, key, value)

  defp truthy?(true), do: true
  defp truthy?(_), do: false
end
