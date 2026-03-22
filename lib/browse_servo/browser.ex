defmodule BrowseServo.Browser do
  @moduledoc """
  Elixir process boundary around the native BrowseServo runtime.

  Telemetry events are emitted under the `[:browse_servo, :browser, ...]` prefix.
  """

  use GenServer

  alias BrowseServo.Page

  @type native_runtime :: term()
  @type page_ref :: %{id: pos_integer(), title: String.t(), url: String.t()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec capabilities(pid()) :: {:ok, map()} | {:error, term()}
  def capabilities(browser) do
    GenServer.call(browser, :capabilities)
  end

  @spec current_url(pid()) :: {:ok, String.t()} | {:error, term()}
  def current_url(browser) do
    GenServer.call(browser, :current_url)
  end

  @spec navigate(pid(), String.t()) :: :ok | {:error, term()}
  def navigate(browser, url) when is_binary(url) do
    GenServer.call(browser, {:navigate, url})
  end

  @spec new_page(pid(), keyword()) :: {:ok, Page.t()} | {:error, term()}
  def new_page(browser, opts \\ []) do
    GenServer.call(browser, {:new_page, opts})
  end

  @spec goto(pid(), Page.t(), String.t()) :: {:ok, Page.t()} | {:error, term()}
  def goto(browser, %Page{} = page, url) when is_binary(url) do
    GenServer.call(browser, {:goto, page.id, url})
  end

  @spec content(pid()) :: {:ok, String.t()} | {:error, term()}
  def content(browser) do
    GenServer.call(browser, :content)
  end

  @spec content(pid(), Page.t()) :: {:ok, String.t()} | {:error, term()}
  def content(browser, %Page{} = page) do
    GenServer.call(browser, {:content, page.id})
  end

  @spec title(pid(), Page.t()) :: {:ok, String.t()} | {:error, term()}
  def title(browser, %Page{} = page) do
    GenServer.call(browser, {:title, page.id})
  end

  @spec evaluate(pid(), String.t()) :: {:ok, term()} | {:error, term()}
  def evaluate(browser, expression) when is_binary(expression) do
    GenServer.call(browser, {:evaluate, expression})
  end

  @spec evaluate(pid(), Page.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def evaluate(browser, %Page{} = page, expression) when is_binary(expression) do
    GenServer.call(browser, {:evaluate, page.id, expression})
  end

  @spec capture_screenshot(pid(), keyword()) :: {:ok, binary()} | {:error, term()}
  def capture_screenshot(browser, opts \\ []) do
    GenServer.call(browser, {:capture_screenshot, opts})
  end

  @spec close_page(pid(), Page.t()) :: :ok | {:error, term()}
  def close_page(browser, %Page{} = page) do
    GenServer.call(browser, {:close_page, page.id})
  end

  @impl true
  def init(opts) do
    native = native_module(opts)

    :telemetry.span([:browse_servo, :browser, :init], %{native_module: inspect(native)}, fn ->
      with {:ok, runtime} <- native.new_runtime(),
           {:ok, attrs} <- native.open_page(runtime, "about:blank") do
        state = %{
          native: native,
          runtime: runtime,
          current_page: page_ref(attrs),
          screenshot_module: screenshot_module(opts)
        }

        {{:ok, state}, %{status: :ok, page_id: state.current_page.id, url: state.current_page.url}}
      else
        {:error, reason} ->
          {{:stop, reason}, %{status: :error, reason: reason}}

        other ->
          {{:stop, other}, %{status: :error, reason: other}}
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

  def handle_call(:current_url, _from, state) do
    {:reply, {:ok, state.current_page.url}, state}
  end

  def handle_call({:navigate, url}, _from, state) do
    page_id = state.current_page.id

    {reply, next_state} =
      telemetry_call(:navigate, %{browser: self(), page_id: page_id, url: url}, fn ->
        case state.native.navigate(state.runtime, page_id, url) do
          {:ok, attrs} ->
            {:ok, :ok, %{state | current_page: page_ref(attrs)}}

          {:error, reason} ->
            {:error, reason, state}
        end
      end)

    {:reply, reply, next_state}
  end

  def handle_call({:new_page, opts}, _from, state) do
    url = Keyword.get(opts, :url, "about:blank")

    {reply, next_state} =
      telemetry_call(:new_page, %{browser: self(), url: url}, fn ->
        case state.native.open_page(state.runtime, url) do
          {:ok, attrs} ->
            page = page_from_attrs(self(), attrs)
            {:ok, {:ok, page}, %{state | current_page: page_ref(attrs)}}

          {:error, reason} ->
            {:error, reason, state}
        end
      end)

    {:reply, reply, next_state}
  end

  def handle_call({:goto, page_id, url}, _from, state) do
    {reply, next_state} =
      telemetry_call(:goto, %{browser: self(), page_id: page_id, url: url}, fn ->
        case state.native.navigate(state.runtime, page_id, url) do
          {:ok, attrs} ->
            page = page_from_attrs(self(), attrs)
            {:ok, {:ok, page}, maybe_update_current_page(state, page_id, attrs)}

          {:error, reason} ->
            {:error, reason, state}
        end
      end)

    {:reply, reply, next_state}
  end

  def handle_call(:content, _from, state) do
    reply =
      telemetry_span(:content, %{browser: self(), page_id: state.current_page.id}, fn ->
        state.native.content(state.runtime, state.current_page.id)
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

  def handle_call({:evaluate, expression}, _from, state) do
    reply =
      telemetry_span(
        :evaluate,
        %{
          browser: self(),
          page_id: state.current_page.id,
          expression_length: byte_size(expression)
        },
        fn ->
          state.native.evaluate(state.runtime, state.current_page.id, expression)
        end
      )

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

  def handle_call({:capture_screenshot, opts}, _from, state) do
    format = Keyword.get(opts, :format, "png")
    quality = Keyword.get(opts, :quality, 90)

    reply =
      telemetry_span(
        :capture_screenshot,
        %{browser: self(), format: format, page_id: state.current_page.id, quality: quality},
        fn ->
          perform_capture_screenshot(state, opts)
        end
      )

    {:reply, reply, state}
  end

  def handle_call({:close_page, page_id}, _from, state) do
    {reply, next_state} =
      telemetry_call(:close_page, %{browser: self(), page_id: page_id}, fn ->
        case state.native.close_page(state.runtime, page_id) do
          :ok ->
            {:ok, :ok, maybe_clear_current_page(state, page_id)}

          {:error, reason} ->
            {:error, reason, state}

          other ->
            {:ok, other, state}
        end
      end)

    {:reply, reply, next_state}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.execute(
      [:browse_servo, :browser, :terminate],
      %{system_time: System.system_time()},
      %{
        browser: self()
      }
    )

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

  defp page_ref(attrs) do
    %{id: Map.fetch!(attrs, :id), title: Map.fetch!(attrs, :title), url: Map.fetch!(attrs, :url)}
  end

  defp native_module(opts) do
    Keyword.get(
      opts,
      :native_module,
      Application.get_env(:browse_servo, :native_module, BrowseServo.Native)
    )
  end

  defp screenshot_module(opts) do
    Keyword.get(
      opts,
      :screenshot_module,
      Application.get_env(:browse_servo, :screenshot_module, BrowseServo.Screenshot)
    )
  end

  defp maybe_update_current_page(state, page_id, attrs) do
    if state.current_page.id == page_id do
      %{state | current_page: page_ref(attrs)}
    else
      state
    end
  end

  defp maybe_clear_current_page(state, page_id) do
    if state.current_page.id == page_id do
      %{state | current_page: %{id: 0, title: "", url: "about:blank"}}
    else
      state
    end
  end

  defp telemetry_call(event, metadata, fun) do
    :telemetry.span([:browse_servo, :browser, event], metadata, fn ->
      case fun.() do
        {:ok, reply, next_state} ->
          {{reply, next_state}, telemetry_metadata(reply)}

        {:error, reason, next_state} ->
          {{{:error, reason}, next_state}, telemetry_metadata({:error, reason})}
      end
    end)
  end

  defp perform_capture_screenshot(
         %{current_page: %{url: url}, screenshot_module: screenshot_module},
         opts
       ) do
    screenshot_module.capture(url, opts)
  end

  defp telemetry_span(event, metadata, fun) do
    :telemetry.span([:browse_servo, :browser, event], metadata, fn ->
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
  defp summarize(value) when is_atom(value), do: %{type: :atom, value: value}
  defp summarize(value), do: %{type: value}
end
