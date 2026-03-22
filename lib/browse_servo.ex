defmodule BrowseServo do
  @moduledoc """
  Public entrypoint for the BrowseServo browser runtime.
  """

  alias BrowseServo.Browser
  alias BrowseServo.BrowserPool

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    Browser.start_link(opts)
  end

  @doc """
  Builds child specs from pools configured under `:browse_servo`.
  """
  @spec children() :: [Supervisor.child_spec()]
  def children do
    configured_pools()
    |> Keyword.keys()
    |> Enum.map(&BrowserPool.child_spec/1)
  end

  @doc """
  Checks out a browser from the configured default pool.
  """
  @spec checkout((pid() -> term()), keyword()) :: term()
  def checkout(fun, opts) when is_function(fun, 1) and is_list(opts) do
    checkout(default_pool!(), fun, opts)
  end

  @doc """
  Checks out a browser from the configured default pool.
  """
  @spec checkout((pid() -> term())) :: term()
  def checkout(fun) when is_function(fun, 1) do
    checkout(default_pool!(), fun, [])
  end

  @doc """
  Checks out a browser from the pool, runs the given function, and checks it back in.
  """
  @spec checkout(NimblePool.pool(), (pid() -> {term(), :ok | :remove}), keyword()) :: term()
  def checkout(pool, fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    :telemetry.span([:browse_servo, :checkout], %{pool: pool, timeout: timeout}, fn ->
      result = BrowserPool.checkout(pool, fun, timeout)
      {result, %{pool: pool, timeout: timeout}}
    end)
  end

  @spec default_pool!() :: NimblePool.pool()
  def default_pool! do
    Application.fetch_env!(:browse_servo, :default_pool)
  end

  @spec configured_pools() :: keyword()
  def configured_pools do
    Application.get_env(:browse_servo, :pools, [])
  end
end
