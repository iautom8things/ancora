defmodule Ancora.Prime do
  @moduledoc """
  Composes status, current-change guidance, and the local agent loop.
  """

  alias Ancora.Next
  alias Ancora.Output
  alias Ancora.Status

  @spec build(Path.t(), keyword()) :: {:ok, map()} | {:env, String.t()}
  def build(root, opts \\ []) when is_binary(root) and is_list(opts) do
    with {:ok, status} <- Status.build(root, opts),
         {:ok, next} <- Next.build(root, opts) do
      lines =
        ["Spec Led Prime", "", "Status"] ++
          drop_header(status.lines) ++
          ["", "Next"] ++
          drop_header(next.lines) ++
          [
            "",
            "Loop",
            "* Read only the subjects named by spec.next or the task's Advances field.",
            "* Make the smallest code, test, and current-truth change that agrees.",
            "* Run mix spec.next after code, docs, or tests change.",
            "* When ready, run mix spec.check --base #{next.base}.",
            Output.read_protocol()
          ]

      {:ok, %{lines: lines}}
    end
  end

  defp drop_header([_header | lines]), do: lines
  defp drop_header([]), do: []
end
