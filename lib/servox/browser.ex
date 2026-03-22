defmodule Servox.Browser do
  @moduledoc """
  Elixir process boundary around the native Servox runtime.

  Telemetry events are emitted under the `[:servox, :browser, ...]` prefix.
  """

  use GenServer

  alias Servox.Page

  @type native_runtime :: term()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec capabilities(pid()) :: {:ok, map()} | {:error, term()}
  def capabilities(browser) do
    GenServer.call(browser, :capabilities)
  end

  @spec new_page(pid(), keyword()) :: {:ok, Page.t()} | {:error, term()}
  def new_page(browser, opts \\ []) do
    GenServer.call(browser, {:new_page, opts})
  end

  @spec goto(pid(), Page.t(), String.t()) :: {:ok, Page.t()} | {:error, term()}
  def goto(browser, %Page{} = page, url) when is_binary(url) do
    GenServer.call(browser, {:goto, page.id, url})
  end

  @spec content(pid(), Page.t()) :: {:ok, String.t()} | {:error, term()}
  def content(browser, %Page{} = page) do
    GenServer.call(browser, {:content, page.id})
  end

  @spec title(pid(), Page.t()) :: {:ok, String.t()} | {:error, term()}
  def title(browser, %Page{} = page) do
    GenServer.call(browser, {:title, page.id})
  end

  @spec evaluate(pid(), Page.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def evaluate(browser, %Page{} = page, expression) when is_binary(expression) do
    GenServer.call(browser, {:evaluate, page.id, expression})
  end

  @spec close_page(pid(), Page.t()) :: :ok | {:error, term()}
  def close_page(browser, %Page{} = page) do
    GenServer.call(browser, {:close_page, page.id})
  end

  @impl true
  def init(opts) do
    native = native_module(opts)

    :telemetry.span([:servox, :browser, :init], %{native_module: inspect(native)}, fn ->
      case native.new_runtime() do
        {:ok, runtime} ->
          {{:ok, %{native: native, runtime: runtime}}, %{status: :ok}}

        {:error, reason} ->
          {{:stop, reason}, %{status: :error, reason: reason}}
      end
    end)
  end

  @impl true
  def handle_call(:capabilities, _from, state) do
    reply =
      telemetry_span(:capabilities, %{browser: self()}, fn ->
        state.native.capabilities(state.runtime)
      end)

    {:reply, reply, state}
  end

  def handle_call({:new_page, opts}, _from, state) do
    url = Keyword.get(opts, :url, "about:blank")

    reply =
      telemetry_span(:new_page, %{browser: self(), url: url}, fn ->
        with {:ok, attrs} <- state.native.open_page(state.runtime, url) do
          {:ok, page_from_attrs(self(), attrs)}
        end
      end)

    {:reply, reply, state}
  end

  def handle_call({:goto, page_id, url}, _from, state) do
    reply =
      telemetry_span(:goto, %{browser: self(), page_id: page_id, url: url}, fn ->
        with {:ok, attrs} <- state.native.navigate(state.runtime, page_id, url) do
          {:ok, page_from_attrs(self(), attrs)}
        end
      end)

    {:reply, reply, state}
  end

  def handle_call({:content, page_id}, _from, state) do
    reply =
      telemetry_span(:content, %{browser: self(), page_id: page_id}, fn ->
        state.native.content(state.runtime, page_id)
      end)

    {:reply, reply, state}
  end

  def handle_call({:title, page_id}, _from, state) do
    reply =
      telemetry_span(:title, %{browser: self(), page_id: page_id}, fn ->
        state.native.title(state.runtime, page_id)
      end)

    {:reply, reply, state}
  end

  def handle_call({:evaluate, page_id, expression}, _from, state) do
    reply =
      telemetry_span(
        :evaluate,
        %{browser: self(), page_id: page_id, expression_length: byte_size(expression)},
        fn ->
          state.native.evaluate(state.runtime, page_id, expression)
        end
      )

    {:reply, reply, state}
  end

  def handle_call({:close_page, page_id}, _from, state) do
    reply =
      telemetry_span(:close_page, %{browser: self(), page_id: page_id}, fn ->
        state.native.close_page(state.runtime, page_id)
      end)

    {:reply, reply, state}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.execute([:servox, :browser, :terminate], %{system_time: System.system_time()}, %{
      browser: self()
    })

    _ = state.native.shutdown(state.runtime)
    :ok
  end

  defp page_from_attrs(browser, attrs) do
    %Page{
      browser: browser,
      id: Map.fetch!(attrs, :id),
      title: Map.fetch!(attrs, :title),
      url: Map.fetch!(attrs, :url)
    }
  end

  defp native_module(opts) do
    Keyword.get(opts, :native_module, Application.get_env(:servox, :native_module, Servox.Native))
  end

  defp telemetry_span(event, metadata, fun) do
    :telemetry.span([:servox, :browser, event], metadata, fn ->
      result = fun.()
      {result, telemetry_metadata(result)}
    end)
  end

  defp telemetry_metadata({:ok, %Page{} = page}),
    do: %{status: :ok, page_id: page.id, url: page.url}

  defp telemetry_metadata({:ok, value}), do: %{status: :ok, result: summarize(value)}
  defp telemetry_metadata(:ok), do: %{status: :ok}
  defp telemetry_metadata({:error, reason}), do: %{status: :error, reason: reason}
  defp telemetry_metadata({:stop, reason}), do: %{status: :error, reason: reason}
  defp telemetry_metadata(other), do: %{status: :ok, result: summarize(other)}

  defp summarize(value) when is_binary(value), do: %{type: :binary, size: byte_size(value)}
  defp summarize(value) when is_map(value), do: %{type: :map, size: map_size(value)}
  defp summarize(value) when is_list(value), do: %{type: :list, size: length(value)}
  defp summarize(value) when is_tuple(value), do: %{type: :tuple, size: tuple_size(value)}
  defp summarize(value), do: %{type: value}
end
