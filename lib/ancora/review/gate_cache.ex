defmodule Ancora.Review.GateCache do
  @moduledoc """
  Hands `spec.check`'s gate result to a later `spec.review` of the same tree.

  CI runs both tasks back to back in separate VMs, and review needs the same
  gate result check just computed. Check stores the fields review reads at
  `_build/ancora/gate.etf`, and only when git ignores that path, so the file
  can never be committed. The stored key covers every gate input: ancora's
  code, the toolchain, the base and HEAD commits, and the content of every
  dirty, untracked or (inside the scanned paths) ignored file.

  Review uses the file only on an exact key match and recomputes the gate on
  any miss, including a missing, stale, truncated or malformed file.
  `spec.check` never reads it, so no gate verdict comes from it.
  """

  alias Ancora.Git
  alias Ancora.TempName

  @path "_build/ancora/gate.etf"
  @format 1
  @fields [:all_findings, :checked, :errors, :warnings, :fail, :review_data]
  @deps [:yaml_elixir, :zoi, :jason, :earmark_parser]

  @doc "The cache file path relative to the project root."
  @spec path() :: String.t()
  def path, do: @path

  @doc """
  Fingerprints every gate input for `preflight`.

  Returns `:error` when any input cannot be read; callers then skip the cache.
  """
  @spec key(map()) :: {:ok, binary()} | :error
  def key(%{root: root} = preflight) do
    with {:ok, code} <- code_fingerprint(),
         {:ok, base} <- commit(root, preflight.base),
         {:ok, head} <- commit(root, "HEAD"),
         {:ok, dirty} <- status(root, []),
         {:ok, scanned} <-
           status(root, ["--ignored=traditional", "--" | scanned_paths(preflight)]) do
      ignored = Enum.filter(scanned, &match?({"!!", _path}, &1))

      fingerprint =
        {@format, code, System.version(), System.otp_release(), root, preflight.spec_dir, base,
         head, Enum.map(dirty ++ ignored, &file_fingerprint(root, &1))}

      {:ok, :crypto.hash(:sha256, :erlang.term_to_binary(fingerprint))}
    else
      _ -> :error
    end
  end

  @doc """
  Stores the review fields of `report` under `key`.

  Writes only when the key still matches the tree after the gate ran and git
  ignores the cache path. Never raises and never prints.
  """
  @spec store(map(), {:ok, binary()} | :error, map()) :: :ok
  def store(preflight, {:ok, key}, report) do
    if key(preflight) == {:ok, key} and ignored?(preflight.root) do
      write(
        Path.join(preflight.root, @path),
        {__MODULE__, @format, key, Map.take(report, @fields)}
      )
    end

    :ok
  end

  def store(_preflight, :error, _report), do: :ok

  @doc """
  Returns the stored review fields when the file's key matches the tree.

  A tracked or un-ignored file can never match: the key covers that file's own
  content through `git status`, or the commit that holds it through HEAD.
  """
  @spec fetch(map()) :: {:ok, map()} | :miss
  def fetch(preflight) do
    with {:ok, key} <- key(preflight),
         {:ok, binary} <- File.read(Path.join(preflight.root, @path)),
         {__MODULE__, @format, ^key, payload} <- decode(binary),
         %{all_findings: findings, checked: %{}, review_data: %{}, fail: fail} = payload
         when is_list(findings) and is_boolean(fail) <- payload do
      {:ok, payload}
    else
      _ -> :miss
    end
  end

  defp write(path, term) do
    tmp = "#{path}.#{TempName.cross_vm_suffix()}"

    try do
      File.mkdir_p!(Path.dirname(path))
      File.write!(tmp, :erlang.term_to_binary(term))
      File.rename!(tmp, path)
    rescue
      _exception -> File.rm(tmp)
    end
  end

  defp decode(binary) do
    :erlang.binary_to_term(binary)
  rescue
    ArgumentError -> :error
  end

  defp ignored?(root), do: match?({:ok, _}, Git.run(root, ["check-ignore", "-q", @path]))

  defp commit(root, ref) do
    case Git.run(root, ["rev-parse", "--verify", "--quiet", "#{ref}^{commit}"]) do
      {:ok, oid} -> {:ok, String.trim(oid)}
      error -> error
    end
  end

  defp status(root, args) do
    with {:ok, output} <-
           Git.run(root, [
             "status",
             "--porcelain=v1",
             "-z",
             "--untracked-files=all",
             "--no-renames" | args
           ]) do
      entries =
        for <<xy::binary-size(2), " ", path::binary>> <- String.split(output, <<0>>, trim: true),
            do: {xy, path}

      {:ok, entries}
    end
  end

  defp scanned_paths(preflight) do
    Enum.uniq([preflight.spec_dir | preflight.config.test_paths ++ preflight.project.lib_paths])
  end

  defp file_fingerprint(root, {xy, path}) do
    case File.read(Path.join(root, path)) do
      {:ok, content} -> {xy, path, :crypto.hash(:sha256, content)}
      {:error, reason} -> {xy, path, reason}
    end
  end

  defp code_fingerprint do
    Enum.each([:ancora | @deps], &Application.load/1)

    case Application.spec(:ancora, :modules) do
      [_ | _] = modules ->
        {:ok,
         {Enum.map(modules, &{&1, &1.module_info(:md5)}),
          Enum.map([:ancora | @deps], &{&1, Application.spec(&1, :vsn)})}}

      _ ->
        :error
    end
  end
end
