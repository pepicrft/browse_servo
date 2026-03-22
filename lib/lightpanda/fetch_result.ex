defmodule Lightpanda.FetchResult do
  @moduledoc """
  Result returned by `Lightpanda.fetch/2`.
  """

  @enforce_keys [:binary_path, :command, :exit_status, :output, :url]
  defstruct [:binary_path, :command, :exit_status, :output, :url]

  @type t :: %__MODULE__{
          binary_path: String.t(),
          command: [String.t()],
          exit_status: non_neg_integer(),
          output: String.t(),
          url: String.t()
        }
end
