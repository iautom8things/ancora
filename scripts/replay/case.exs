defmodule AncoraReplay.Case do
  @moduledoc false

  @enforce_keys [:name, :repo, :sha, :kind, :functions]
  defstruct [:name, :repo, :sha, :kind, :functions]

  @type kind :: :drift | :control
  @type t :: %__MODULE__{
          name: String.t(),
          repo: String.t(),
          sha: String.t(),
          kind: kind(),
          functions: [String.t()]
        }
end
