defmodule Lightpanda.Browser do
  @moduledoc """
  Managed Lightpanda browser server process.
  """

  use GenServer

  alias Lightpanda.Binary
  alias Lightpanda.CDP.Client
  alias Lightpanda.Command
  alias Lightpanda.Context
  alias Lightpanda.Page

  @default_host "127.0.0.1"

  @type state :: %{
          client: pid(),
          endpoint: URI.t(),
          host: String.t(),
          port: non_neg_integer(),
          port_handle: port()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec endpoint(pid()) :: {:ok, URI.t()}
  def endpoint(browser) do
    GenServer.call(browser, :endpoint)
  end

  @spec ws_endpoint(pid()) :: {:ok, String.t()}
  def ws_endpoint(browser) do
    GenServer.call(browser, :ws_endpoint)
  end

  @spec new_context(pid()) :: {:ok, Context.t()} | {:error, term()}
  def new_context(browser) do
    GenServer.call(browser, :new_context)
  end

  @spec new_page(pid(), keyword()) :: {:ok, Page.t()} | {:error, term()}
  def new_page(browser, opts \\ []) do
    GenServer.call(browser, {:new_page, opts})
  end

  @spec stop(pid()) :: :ok
  def stop(browser) do
    GenServer.stop(browser)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    host = Keyword.get(opts, :host, @default_host)
    port_number = Keyword.get(opts, :port, 9222)
    serve_opts = Keyword.put_new(opts, :host, host) |> Keyword.put_new(:port, port_number)

    with {:ok, binary_path} <- Binary.ensure_installed(opts),
         port_handle = runner_module().open(binary_path, Command.serve(serve_opts), opts),
         {:ok, endpoint} <- wait_for_endpoint(host, port_number, opts),
         {:ok, client} <- Client.start_link(endpoint["webSocketDebuggerUrl"], owner: self()) do
      {:ok,
       %{
         client: client,
         endpoint: URI.parse("http://#{host}:#{port_number}"),
         host: host,
         port: port_number,
         port_handle: port_handle
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:endpoint, _from, state) do
    {:reply, {:ok, state.endpoint}, state}
  end

  def handle_call(:ws_endpoint, _from, state) do
    {:ok, endpoint} = endpoint_metadata(state)
    {:reply, {:ok, endpoint["webSocketDebuggerUrl"]}, state}
  end

  def handle_call(:new_context, _from, state) do
    reply =
      with {:ok, %{"browserContextId" => context_id}} <-
             Client.command(state.client, "Target.createBrowserContext") do
        {:ok, %Context{browser: self(), id: context_id}}
      end

    {:reply, reply, state}
  end

  def handle_call({:new_page, opts}, _from, state) do
    context_id =
      case Keyword.get(opts, :context) do
        %Context{id: id} -> id
        _ -> nil
      end

    reply =
      with {:ok, %{"targetId" => target_id}} <-
             Client.command(
               state.client,
               "Target.createTarget",
               Map.merge(%{"url" => "about:blank"}, context_params(context_id))
             ),
           {:ok, %{"sessionId" => session_id}} <-
             Client.command(
               state.client,
               "Target.attachToTarget",
               %{"flatten" => true, "targetId" => target_id}
             ),
           :ok <- enable_page_domains(state.client, session_id) do
        {:ok,
         %Page{
           browser: self(),
           client: state.client,
           context_id: context_id,
           session_id: session_id,
           target_id: target_id
         }}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_info({_port, {:data, _line}}, state), do: {:noreply, state}

  def handle_info({_port, {:exit_status, status}}, state) do
    {:stop, {:lightpanda_exited, status}, state}
  end

  @impl true
  def terminate(_reason, state) do
    Client.close(state.client)
    runner_module().close(state.port_handle)
    :ok
  end

  defp enable_page_domains(client, session_id) do
    commands = [
      {"Page.enable", %{}},
      {"Page.setLifecycleEventsEnabled", %{"enabled" => true}},
      {"Runtime.enable", %{}},
      {"DOM.enable", %{}},
      {"Network.enable", %{}}
    ]

    Enum.reduce_while(commands, :ok, fn {method, params}, :ok ->
      case Client.command(client, method, params, session_id: session_id) do
        {:ok, _result} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp wait_for_endpoint(host, port_number, opts) do
    timeout = Keyword.get(opts, :startup_timeout, 5_000)
    started_at = System.monotonic_time(:millisecond)
    do_wait_for_endpoint(host, port_number, timeout, started_at)
  end

  defp do_wait_for_endpoint(host, port_number, timeout, started_at) do
    if System.monotonic_time(:millisecond) - started_at > timeout do
      {:error, :lightpanda_startup_timeout}
    else
      case endpoint_metadata(%{host: host, port: port_number}) do
        {:ok, metadata} ->
          {:ok, metadata}

        _ ->
          Process.sleep(50)
          do_wait_for_endpoint(host, port_number, timeout, started_at)
      end
    end
  end

  defp endpoint_metadata(%{host: host, port: port_number}) do
    url = "http://#{host}:#{port_number}/json/version"

    try do
      {:ok, http_module().get_json!(url)}
    rescue
      _error -> {:error, :endpoint_unavailable}
    end
  end

  defp context_params(nil), do: %{}
  defp context_params(context_id), do: %{"browserContextId" => context_id}

  defp runner_module do
    Application.get_env(:lightpanda, :runner, Lightpanda.Runner)
  end

  defp http_module do
    Application.get_env(:lightpanda, :http_client, Lightpanda.HTTP)
  end
end
