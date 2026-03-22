defmodule Lightpanda.Context do
  @moduledoc """
  A Lightpanda browser context.
  """

  @enforce_keys [:browser, :id]
  defstruct [:browser, :id]

  @type t :: %__MODULE__{
          browser: pid(),
          id: String.t()
        }
end
