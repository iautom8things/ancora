defmodule Ancora.Output do
  @moduledoc """
  The only stdout writer in ancora.

  Gate tasks (`spec.check`, `spec.validate`) run inside the gated wrapper, which
  classifies the outcome as `:ok`, `:usage`, `:env`, or `:internal`. The
  first three emit a verdict via `Ancora.Output.Verdict`; `:internal`
  re-raises with no verdict line. Report tasks use the same wrapper for
  error paths and print the message without a verdict.

  `[CONFIG]` diagnostics and Logger output go to stderr. Human-readable
  formatters never produce the substring `result=`. JSON values remain intact,
  but the encoded line cannot match the verdict grammar.
  """

  alias Ancora.Finding
  alias Ancora.Output.Verdict

  @read_protocol "The verdict is the last stdout line: `spec.check result=…`. A non-zero exit with no verdict line means the run crashed before the gate finished — treat it as failure."

  @gate_tasks MapSet.new(["spec.check", "spec.validate"])

  @doc """
  The read-protocol sentence quoted by `mix help spec.check` and
  `spec.prime`'s loop footer.
  """
  @spec read_protocol() :: String.t()
  def read_protocol, do: @read_protocol

  @doc """
  Run `fun` inside the single emission wrapper.

  `fun` must return `{:ok, report}`, `{:usage, message}`, `{:env, message}`,
  or `{:internal, exception}`. Any raised exception is classified
  `:internal` and re-raised with no verdict.
  """
  @spec gated(String.t(), (-> term())) :: :ok | no_return()
  def gated(task_name, fun) when is_binary(task_name) and is_function(fun, 0) do
    gated(task_name, [], fun)
  end

  @doc "Run `fun` with emission options. `:json` applies only to gate failure paths."
  @spec gated(String.t(), keyword(), (-> term())) :: :ok | no_return()
  def gated(task_name, opts, fun)
      when is_binary(task_name) and is_list(opts) and is_function(fun, 0) do
    pin_logger_to_stderr()

    case classify(fun) do
      {:ok, report} ->
        render(report)

        if gate?(task_name) do
          Verdict.emit(task_name, report)
          unless passed?(report), do: Mix.raise("#{task_name} failed")
        end

        :ok

      {:usage, msg} ->
        fail_path(task_name, msg, :usage, opts)

      {:env, msg} ->
        fail_path(task_name, msg, :env, opts)

      {:internal, exception, stacktrace} ->
        reraise exception, stacktrace
    end
  end

  @doc """
  Pin the default Logger handler to stderr.

  `logger_std_h` refuses a type change on a live handler, so this removes
  and re-adds `:default` when it is currently writing to standard_io.
  """
  @spec pin_logger_to_stderr() :: :ok
  def pin_logger_to_stderr do
    set_default_logger_device(:standard_error)
  end

  defp set_default_logger_device(type) when type in [:standard_io, :standard_error] do
    case :logger.get_handler_config(:default) do
      {:ok, %{config: %{type: ^type}}} ->
        :ok

      {:ok, handler} ->
        _ = :logger.remove_handler(:default)

        handler_config = %{
          level: handler.level,
          filters: handler.filters,
          filter_default: handler.filter_default,
          formatter: handler.formatter,
          config: Map.put(handler.config, :type, type)
        }

        case :logger.add_handler(:default, handler.module, handler_config) do
          :ok ->
            :ok

          {:error, _} ->
            _ = Logger.configure_backend(:console, device: logger_backend_device(type))
            :ok
        end

      {:error, _} ->
        _ = Logger.configure_backend(:console, device: logger_backend_device(type))
        :ok
    end
  end

  defp logger_backend_device(:standard_error), do: :standard_error
  defp logger_backend_device(:standard_io), do: :user

  @doc "Write a `[CONFIG]` diagnostic to stderr. Never stdout."
  @spec config_diagnostic(String.t()) :: :ok
  def config_diagnostic(message) when is_binary(message) do
    IO.puts(:stderr, "[CONFIG] #{sanitize(message)}")
    :ok
  end

  @doc """
  Write one line to stdout.

  The read-protocol sentence is written verbatim (it names `result=` as
  documentation). Every other line is sanitized so it cannot contain
  `result=`.
  """
  @spec puts(String.t()) :: :ok
  def puts(line) when is_binary(line) do
    IO.puts(if line == @read_protocol, do: line, else: sanitize(line))
    :ok
  end

  @doc """
  Format one finding as `[SEV] <subject> <code> <file> :: <message>`.
  """
  @spec finding_line(Finding.t()) :: String.t()
  def finding_line(%Finding{} = finding) do
    sev = sev_token(finding.severity)
    subject = blank(finding.subject)
    file = blank(finding.file)
    message = finding.message || ""
    sanitize("[#{sev}] #{subject} #{finding.code} #{file} :: #{message}")
  end

  @doc "Warnings first, then info, then errors last. Stable within a band."
  @spec sort_findings([Finding.t()]) :: [Finding.t()]
  def sort_findings(findings) when is_list(findings) do
    Enum.sort_by(findings, &sort_rank/1)
  end

  @doc "Summary line `checked subjects=<N> requirements=<N> errors=<E> warnings=<W>`."
  @spec checked_summary(map()) :: String.t()
  def checked_summary(summary) when is_map(summary) do
    subjects = fetch_count(summary, :subjects)
    requirements = fetch_count(summary, :requirements)
    errors = fetch_count(summary, :errors)
    warnings = fetch_count(summary, :warnings)

    sanitize(
      "checked subjects=#{subjects} requirements=#{requirements} errors=#{errors} warnings=#{warnings}"
    )
  end

  @doc """
  Branch summary
  `branch base=<ref> changed_files=<N> findings=<N> (total error=E warning=W info=I)`.
  """
  @spec branch_summary(map()) :: String.t()
  def branch_summary(branch) when is_map(branch) do
    base = branch[:base] || branch["base"] || "-"
    changed = fetch_count(branch, :changed_files)
    findings = fetch_count(branch, :findings)
    errors = fetch_count(branch, :errors)
    warnings = fetch_count(branch, :warnings)
    info = fetch_count(branch, :info)

    sanitize(
      "branch base=#{base} changed_files=#{changed} findings=#{findings} " <>
        "(total error=#{errors} warning=#{warnings} info=#{info})"
    )
  end

  @doc "Guidance line `branch impacted_subjects=…`."
  @spec guidance_impacted([String.t()] | String.t()) :: String.t()
  def guidance_impacted(subjects) when is_list(subjects) do
    sanitize("branch impacted_subjects=#{Enum.join(subjects, ",")}")
  end

  def guidance_impacted(subjects) when is_binary(subjects) do
    sanitize("branch impacted_subjects=#{subjects}")
  end

  @doc "Guidance line `branch next=…`."
  @spec guidance_next(String.t()) :: String.t()
  def guidance_next(command) when is_binary(command) do
    sanitize("branch next=#{command}")
  end

  @doc "JSON encoding of a report map."
  @spec json_payload(map()) :: String.t()
  def json_payload(report) when is_map(report) do
    report
    |> Map.delete(:json)
    |> json_safe()
    |> Jason.encode!()
  end

  defp fail_path(task_name, msg, tier, opts) do
    if gate?(task_name) and Keyword.get(opts, :json, false) do
      %{tier: tier, fail: true, message: msg}
      |> Ancora.Gate.json_report()
      |> render()
    else
      puts(msg)
    end

    if gate?(task_name) do
      Verdict.emit_fail(task_name, tier)
    end

    Mix.raise(msg)
  end

  defp classify(fun) do
    try do
      case fun.() do
        {:ok, report} when is_map(report) ->
          {:ok, report}

        {:usage, msg} when is_binary(msg) ->
          {:usage, msg}

        {:env, msg} when is_binary(msg) ->
          {:env, msg}

        {:internal, %{__exception__: true} = exception} ->
          {:internal, exception, []}

        other ->
          {:internal, %RuntimeError{message: "ungated return from #{inspect(other)}"}, []}
      end
    rescue
      exception ->
        {:internal, exception, __STACKTRACE__}
    end
  end

  defp render(report) when is_map(report) do
    if json?(report) do
      IO.puts(json_payload(report))
    else
      render_text(report)
    end
  end

  defp render_text(report) do
    report
    |> Map.get(:findings, [])
    |> sort_findings()
    |> Enum.each(fn finding -> puts(finding_line(finding)) end)

    case Map.get(report, :checked) do
      summary when is_map(summary) -> puts(checked_summary(summary))
      _ -> :ok
    end

    case Map.get(report, :branch) do
      branch when is_map(branch) -> puts(branch_summary(branch))
      _ -> :ok
    end

    case Map.get(report, :guidance) do
      guidance when is_map(guidance) ->
        if Map.has_key?(guidance, :impacted_subjects) or
             Map.has_key?(guidance, "impacted_subjects") do
          puts(guidance_impacted(guidance[:impacted_subjects] || guidance["impacted_subjects"]))
        end

        if next = guidance[:next] || guidance["next"] do
          puts(guidance_next(next))
        end

      _ ->
        :ok
    end

    report
    |> Map.get(:lines, [])
    |> List.wrap()
    |> Enum.each(&puts/1)
  end

  defp passed?(report) do
    cond do
      Map.get(report, :fail) == true ->
        false

      Map.get(report, :pass) == true ->
        true

      true ->
        {errors, warnings} = Verdict.counts(report)
        errors == 0 and warnings == 0
    end
  end

  defp gate?(task_name), do: MapSet.member?(@gate_tasks, task_name)

  defp json?(report), do: Map.get(report, :json) == true

  defp sev_token(:error), do: "ERROR"
  defp sev_token(:warning), do: "WARNING"
  defp sev_token(:info), do: "INFO"
  defp sev_token(_), do: "-"

  defp sort_rank(%Finding{severity: :warning}), do: 0
  defp sort_rank(%Finding{severity: :info}), do: 1
  defp sort_rank(%Finding{severity: :error}), do: 2
  defp sort_rank(%Finding{}), do: 3

  defp blank(nil), do: "-"
  defp blank(""), do: "-"
  defp blank(value), do: to_string(value)

  defp fetch_count(map, key) do
    case Map.get(map, key) || Map.get(map, Atom.to_string(key)) do
      n when is_integer(n) and n >= 0 -> n
      _ -> 0
    end
  end

  defp json_safe(%Finding{} = finding) do
    %{
      code: finding.code,
      subject: finding.subject,
      file: finding.file,
      message: finding.message,
      severity: finding.severity,
      severity_source: finding.severity_source
    }
  end

  defp json_safe(list) when is_list(list), do: Enum.map(list, &json_safe/1)

  defp json_safe(%_{} = struct), do: struct |> Map.from_struct() |> json_safe()

  defp json_safe(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, json_safe(value)} end)
  end

  defp json_safe(other), do: other

  defp sanitize(text) when is_binary(text) do
    String.replace(text, "result=", "result =")
  end
end
