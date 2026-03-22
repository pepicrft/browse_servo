defmodule Lightpanda.MCP do
  @moduledoc """
  Wrapper for Lightpanda's `mcp` command.
  """

  alias Lightpanda.Binary
  alias Lightpanda.Command

  @spec start_link(keyword()) :: {:ok, port()} | {:error, term()}
  def start_link(opts \\ []) do
    runner = runner_module()

    with {:ok, binary_path} <- Binary.ensure_installed(opts) do
      {:ok, runner.open(binary_path, Command.mcp(opts), opts)}
    end
  rescue
    error -> {:error, error}
  end

  defp runner_module do
    Application.get_env(:lightpanda, :runner, Lightpanda.Runner)
  end
end
