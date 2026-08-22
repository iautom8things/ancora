defmodule Ancora.Trailer do
  @moduledoc """
  Parses `Spec-Ack:` git trailers into a severity override map.

  Grammar: `Spec-Ack: <code>=<info|warning>`. Codes must be registry codes.
  The trailer is downgrade-only: `error` and `off` are rejected at parse,
  and `Ancora.Severity` further rejects a value higher than the resolved
  config severity. There are no presets.

  Unknown codes or severities emit a `[CONFIG]` warning on stderr and are
  ignored, never silently dropped.

  ## Scope: `base..HEAD`, not HEAD-only

  `read/2` shells `git log <base>..HEAD --format=%B` and unions parsed
  overrides across every commit in the range. HEAD-only scanning is
  wrong: CI often sees squash or merge commits where the trailer lives
  one commit deep.

  Trailers are a cooperative self-report. `read/2` does not verify
  signatures or authorship. This is suited to single-author and small-team
  workflows; larger teams should pair trailers with code review.
  """

  alias Ancora.Finding
  alias Ancora.Severity

  @trailer_prefix "Spec-Ack:"

  @severity_tokens %{
    "info" => :info,
    "warning" => :warning
  }

  @rejected_severities MapSet.new(["error", "off"])

  @type override_map :: %{optional(String.t()) => Severity.severity()}
  @type parse_result :: %{overrides: override_map(), warnings: [String.t()]}

  @doc "Parses one or more commit messages into an override map."
  @spec parse(binary()) :: parse_result()
  def parse(body) when is_binary(body) do
    body
    |> String.split(~r/\r?\n/)
    |> Enum.flat_map(&trailer_tokens/1)
    |> Enum.reduce(%{overrides: %{}, warnings: []}, &apply_token/2)
    |> finalize()
  end

  @doc """
  Reads `git log <base>..HEAD --format=%B` in `root` and returns the union
  of parsed overrides across every commit in the range.
  """
  @spec read(String.t(), String.t()) :: parse_result()
  def read(root, base) when is_binary(root) and is_binary(base) do
    case System.cmd(
           "git",
           ["-C", root, "log", "#{base}..HEAD", "--format=%B"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> parse(output)
      {_output, _exit_code} -> %{overrides: %{}, warnings: []}
    end
  end

  defp trailer_tokens(line) do
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, @trailer_prefix) do
      trimmed
      |> String.replace_prefix(@trailer_prefix, "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    else
      []
    end
  end

  defp apply_token(token, acc) do
    if String.contains?(token, "=") do
      apply_pair(token, acc)
    else
      warn(acc, "unknown token #{inspect(token)}")
    end
  end

  defp apply_pair(token, acc) do
    [code, severity_str] =
      token
      |> String.split("=", parts: 2)
      |> Enum.map(&String.trim/1)

    cond do
      code == "" ->
        warn(acc, "unknown token #{inspect(token)}")

      MapSet.member?(@rejected_severities, severity_str) ->
        warn(acc, "rejected severity in #{inspect(token)} (downgrade only: info|warning)")

      not Map.has_key?(@severity_tokens, severity_str) ->
        warn(acc, "unknown severity in #{inspect(token)}")

      not Finding.known?(code) ->
        warn(acc, "unknown code #{inspect(code)}")

      true ->
        merge_overrides(acc, %{code => Map.fetch!(@severity_tokens, severity_str)})
    end
  end

  defp merge_overrides(%{overrides: overrides} = acc, new) do
    %{acc | overrides: Map.merge(overrides, new)}
  end

  defp warn(%{warnings: warnings} = acc, msg) do
    line = "[CONFIG] Spec-Ack: #{msg}"
    IO.puts(:stderr, line)
    %{acc | warnings: [line | warnings]}
  end

  defp finalize(%{warnings: warnings} = acc) do
    %{acc | warnings: warnings |> Enum.reverse() |> Enum.uniq()}
  end
end
