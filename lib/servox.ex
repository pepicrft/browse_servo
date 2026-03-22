defmodule Servox do
  @moduledoc """
  Public entrypoint for the Servox browser runtime.
  """

  alias Servox.Browser

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    Browser.start_link(opts)
  end
end
