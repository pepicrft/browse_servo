defmodule Lightpanda do
  @moduledoc """
  Elixir-first wrapper around the Lightpanda browser.

  The public entrypoints are intentionally small:

  - `fetch/2` for one-shot fetch workflows
  - `launch/1` for a managed CDP server
  - `mcp/1` for MCP mode
  - `version/1` for binary introspection
  """

  alias Lightpanda.Browser
  alias Lightpanda.CLI
  alias Lightpanda.MCP

  @doc """
  Fetches a URL via `lightpanda fetch`.
  """
  @spec fetch(String.t(), keyword()) :: {:ok, Lightpanda.FetchResult.t()} | {:error, term()}
  def fetch(url, opts \\ []) when is_binary(url) do
    CLI.fetch(url, opts)
  end

  @doc """
  Starts a managed Lightpanda `serve` process and connects a CDP client.
  """
  @spec launch(keyword()) :: GenServer.on_start()
  def launch(opts \\ []) do
    Browser.start_link(opts)
  end

  @doc """
  Alias for `launch/1`.
  """
  @spec serve(keyword()) :: GenServer.on_start()
  def serve(opts \\ []) do
    launch(opts)
  end

  @doc """
  Starts Lightpanda in MCP mode and returns the underlying port.
  """
  @spec mcp(keyword()) :: {:ok, port()} | {:error, term()}
  def mcp(opts \\ []) do
    MCP.start_link(opts)
  end

  @doc """
  Returns the resolved Lightpanda browser version string.
  """
  @spec version(keyword()) :: {:ok, String.t()} | {:error, term()}
  def version(opts \\ []) do
    CLI.version(opts)
  end
end
