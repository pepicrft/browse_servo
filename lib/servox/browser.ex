defmodule Servox.Browser do
  @moduledoc """
  Elixir process boundary around the native Servox runtime.
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

    case native.new_runtime() do
      {:ok, runtime} -> {:ok, %{native: native, runtime: runtime}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:capabilities, _from, state) do
    {:reply, state.native.capabilities(state.runtime), state}
  end

  def handle_call({:new_page, opts}, _from, state) do
    url = Keyword.get(opts, :url, "about:blank")

    reply =
      with {:ok, attrs} <- state.native.open_page(state.runtime, url) do
        {:ok, page_from_attrs(self(), attrs)}
      end

    {:reply, reply, state}
  end

  def handle_call({:goto, page_id, url}, _from, state) do
    reply =
      with {:ok, attrs} <- state.native.navigate(state.runtime, page_id, url) do
        {:ok, page_from_attrs(self(), attrs)}
      end

    {:reply, reply, state}
  end

  def handle_call({:content, page_id}, _from, state) do
    {:reply, state.native.content(state.runtime, page_id), state}
  end

  def handle_call({:title, page_id}, _from, state) do
    {:reply, state.native.title(state.runtime, page_id), state}
  end

  def handle_call({:evaluate, page_id, expression}, _from, state) do
    {:reply, state.native.evaluate(state.runtime, page_id, expression), state}
  end

  def handle_call({:close_page, page_id}, _from, state) do
    {:reply, state.native.close_page(state.runtime, page_id), state}
  end

  @impl true
  def terminate(_reason, state) do
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
end
