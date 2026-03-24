defmodule BrowseServo.Browser do
  @moduledoc """
  Elixir process boundary around the native BrowseServo runtime.

  Telemetry events are emitted under the `[:browse_servo, :browser, ...]` prefix.
  """

  use GenServer

  alias BrowseServo.Telemetry

  @type native_runtime :: term()
  @type page_ref :: %{id: pos_integer(), url: String.t()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec current_url(pid()) :: {:ok, String.t()} | {:error, term()}
  def current_url(browser) do
    GenServer.call(browser, :current_url)
  end

  @spec navigate(pid(), String.t()) :: :ok | {:error, term()}
  def navigate(browser, url) when is_binary(url) do
    GenServer.call(browser, {:navigate, url})
  end

  @spec content(pid()) :: {:ok, String.t()} | {:error, term()}
  def content(browser) do
    GenServer.call(browser, :content)
  end

  @spec evaluate(pid(), String.t()) :: {:ok, term()} | {:error, term()}
  def evaluate(browser, expression) when is_binary(expression) do
    GenServer.call(browser, {:evaluate, expression})
  end

  @spec capture_screenshot(pid(), keyword()) :: {:ok, binary()} | {:error, term()}
  def capture_screenshot(browser, opts \\ []) do
    GenServer.call(browser, {:capture_screenshot, opts})
  end

  @spec print_to_pdf(pid(), keyword()) :: {:ok, binary()} | {:error, term()}
  def print_to_pdf(browser, opts \\ []) do
    GenServer.call(browser, {:print_to_pdf, opts})
  end

  @spec click(pid(), term(), keyword()) :: :ok | {:error, term()}
  def click(browser, locator, opts \\ []) do
    GenServer.call(browser, {:click, locator, opts})
  end

  @spec fill(pid(), term(), String.t(), keyword()) :: :ok | {:error, term()}
  def fill(browser, locator, value, opts \\ []) when is_binary(value) do
    GenServer.call(browser, {:fill, locator, value, opts})
  end

  @spec wait_for(pid(), term(), keyword()) :: :ok | {:error, term()}
  def wait_for(browser, locator, opts \\ []) do
    GenServer.call(browser, {:wait_for, locator, opts})
  end

  @spec title(pid()) :: {:ok, String.t()} | {:error, term()}
  def title(browser) do
    GenServer.call(browser, :title)
  end

  @spec go_back(pid(), keyword()) :: :ok | {:error, term()}
  def go_back(browser, opts \\ []) do
    GenServer.call(browser, {:go_back, opts})
  end

  @spec go_forward(pid(), keyword()) :: :ok | {:error, term()}
  def go_forward(browser, opts \\ []) do
    GenServer.call(browser, {:go_forward, opts})
  end

  @spec reload(pid(), keyword()) :: :ok | {:error, term()}
  def reload(browser, opts \\ []) do
    GenServer.call(browser, {:reload, opts})
  end

  @spec select_option(pid(), term(), String.t(), keyword()) :: :ok | {:error, term()}
  def select_option(browser, locator, value, opts \\ []) do
    GenServer.call(browser, {:select_option, locator, value, opts})
  end

  @spec hover(pid(), term(), keyword()) :: :ok | {:error, term()}
  def hover(browser, locator, opts \\ []) do
    GenServer.call(browser, {:hover, locator, opts})
  end

  @spec get_text(pid(), term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def get_text(browser, locator, opts \\ []) do
    GenServer.call(browser, {:get_text, locator, opts})
  end

  @spec get_attribute(pid(), term(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_attribute(browser, locator, name, opts \\ []) do
    GenServer.call(browser, {:get_attribute, locator, name, opts})
  end

  @spec get_cookies(pid(), keyword()) :: {:ok, list()} | {:error, term()}
  def get_cookies(browser, opts \\ []) do
    GenServer.call(browser, {:get_cookies, opts})
  end

  @spec set_cookie(pid(), map(), keyword()) :: :ok | {:error, term()}
  def set_cookie(browser, cookie, opts \\ []) do
    GenServer.call(browser, {:set_cookie, cookie, opts})
  end

  @spec clear_cookies(pid(), keyword()) :: :ok | {:error, term()}
  def clear_cookies(browser, opts \\ []) do
    GenServer.call(browser, {:clear_cookies, opts})
  end

  @impl true
  def init(opts) do
    native = native_module(opts)
    start_time = System.monotonic_time()

    Telemetry.execute([:browser, :init, :start], %{system_time: System.system_time()}, %{
      native_module: inspect(native)
    })

    result =
      with {:ok, runtime} <- native.new_runtime(),
           {:ok, attrs} <- native.open_page(runtime, "about:blank") do
        page = page_ref(attrs)

        state = %{
          native: native,
          runtime: runtime,
          current_page: page,
          history: [page.url],
          history_index: 0
        }

        {:ok, state}
      else
        {:error, reason} ->
          {:stop, reason}

        other ->
          {:stop, other}
      end

    Telemetry.execute(
      [:browser, :init, :stop],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(%{native_module: inspect(native)}, telemetry_metadata(result))
    )

    result
  end

  @impl true
  def handle_call(:current_url, _from, state) do
    {:reply, {:ok, state.current_page.url}, state}
  end

  def handle_call({:navigate, url}, _from, state) do
    page_id = state.current_page.id

    {reply, next_state} =
      telemetry_call(:navigate, %{browser: self(), page_id: page_id, url: url}, fn ->
        case state.native.navigate(state.runtime, page_id, url) do
          {:ok, attrs} ->
            page = page_ref(attrs)
            new_history = Enum.take(state.history, state.history_index + 1) ++ [page.url]

            {:ok, :ok,
             %{
               state
               | current_page: page,
                 history: new_history,
                 history_index: length(new_history) - 1
             }}

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

  def handle_call({:capture_screenshot, opts}, _from, state) do
    format = Keyword.get(opts, :format, "png")
    quality = Keyword.get(opts, :quality, 90)

    reply =
      telemetry_span(
        :capture,
        %{browser: self(), format: format, page_id: state.current_page.id, quality: quality},
        fn ->
          perform_capture_screenshot(state, opts)
        end
      )

    {:reply, reply, state}
  end

  def handle_call({:print_to_pdf, opts}, _from, state) do
    reply =
      telemetry_span(
        :print_to_pdf,
        %{browser: self(), page_id: state.current_page.id, url: state.current_page.url},
        fn ->
          perform_print_to_pdf(state, opts)
        end
      )

    {:reply, reply, state}
  end

  def handle_call({:click, locator, opts}, _from, state) do
    reply =
      telemetry_span(
        :click,
        %{browser: self(), page_id: state.current_page.id, url: state.current_page.url},
        fn ->
          perform_click(state, locator, opts)
        end
      )

    {:reply, reply, state}
  end

  def handle_call({:fill, locator, value, opts}, _from, state) do
    reply =
      telemetry_span(
        :fill,
        %{browser: self(), page_id: state.current_page.id, url: state.current_page.url},
        fn ->
          perform_fill(state, locator, value, opts)
        end
      )

    {:reply, reply, state}
  end

  def handle_call({:wait_for, locator, opts}, _from, state) do
    reply =
      telemetry_span(
        :wait_for,
        %{browser: self(), page_id: state.current_page.id, url: state.current_page.url},
        fn ->
          perform_wait_for(state, locator, opts)
        end
      )

    {:reply, reply, state}
  end

  def handle_call(:title, _from, state) do
    reply =
      telemetry_span(
        :title,
        %{browser: self(), page_id: state.current_page.id},
        fn -> state.native.title(state.runtime, state.current_page.id) end
      )

    {:reply, reply, state}
  end

  def handle_call({:go_back, _opts}, _from, state) do
    case history_url(state, state.history_index - 1) do
      {:ok, url, new_index} ->
        {reply, next_state} =
          navigate_to(state, :go_back, url, history_index: new_index)

        {:reply, reply, next_state}

      :error ->
        {:reply, {:error, :navigation_history_unavailable}, state}
    end
  end

  def handle_call({:go_forward, _opts}, _from, state) do
    case history_url(state, state.history_index + 1) do
      {:ok, url, new_index} ->
        {reply, next_state} =
          navigate_to(state, :go_forward, url, history_index: new_index)

        {:reply, reply, next_state}

      :error ->
        {:reply, {:error, :navigation_history_unavailable}, state}
    end
  end

  def handle_call({:reload, _opts}, _from, state) do
    {reply, next_state} = navigate_to(state, :reload, state.current_page.url)
    {:reply, reply, next_state}
  end

  def handle_call({:select_option, locator, value, opts}, _from, state) do
    reply =
      telemetry_span(
        :select_option,
        %{browser: self(), page_id: state.current_page.id, url: state.current_page.url},
        fn -> perform_select_option(state, locator, value, opts) end
      )

    {:reply, reply, state}
  end

  def handle_call({:hover, locator, opts}, _from, state) do
    reply =
      telemetry_span(
        :hover,
        %{browser: self(), page_id: state.current_page.id, url: state.current_page.url},
        fn -> perform_hover(state, locator, opts) end
      )

    {:reply, reply, state}
  end

  def handle_call({:get_text, locator, opts}, _from, state) do
    reply =
      telemetry_span(
        :get_text,
        %{browser: self(), page_id: state.current_page.id, url: state.current_page.url},
        fn -> perform_get_text(state, locator, opts) end
      )

    {:reply, reply, state}
  end

  def handle_call({:get_attribute, locator, name, opts}, _from, state) do
    reply =
      telemetry_span(
        :get_attribute,
        %{browser: self(), page_id: state.current_page.id, url: state.current_page.url},
        fn -> perform_get_attribute(state, locator, name, opts) end
      )

    {:reply, reply, state}
  end

  def handle_call({:get_cookies, _opts}, _from, state) do
    reply =
      telemetry_span(
        :get_cookies,
        %{browser: self(), page_id: state.current_page.id},
        fn -> state.native.get_cookies(state.runtime, state.current_page.id) end
      )

    {:reply, reply, state}
  end

  def handle_call({:set_cookie, cookie, opts}, _from, state) do
    reply =
      telemetry_span(
        :set_cookie,
        %{browser: self(), page_id: state.current_page.id},
        fn -> perform_set_cookie(state, cookie, opts) end
      )

    {:reply, reply, state}
  end

  def handle_call({:clear_cookies, _opts}, _from, state) do
    reply =
      telemetry_span(
        :clear_cookies,
        %{browser: self(), page_id: state.current_page.id},
        fn -> state.native.clear_cookies(state.runtime, state.current_page.id) end
      )

    {:reply, reply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Telemetry.execute(
      [:browser, :terminate],
      %{system_time: System.system_time()},
      %{
        browser: self()
      }
    )

    _ = state.native.shutdown(state.runtime)
    :ok
  end

  defp page_ref(attrs) do
    %{id: Map.fetch!(attrs, :id), url: Map.fetch!(attrs, :url)}
  end

  defp native_module(opts) do
    Keyword.get(
      opts,
      :native_module,
      Application.get_env(:browse_servo, :native_module, BrowseServo.Native)
    )
  end

  defp telemetry_call(event, metadata, fun) do
    result =
      Telemetry.span(
        [:browser, event],
        metadata,
        fn ->
          fun.()
        end,
        fn
          {:ok, reply, _next_state} -> telemetry_metadata(reply)
          {:error, reason, _next_state} -> telemetry_metadata({:error, reason})
        end
      )

    case result do
      {:ok, reply, next_state} -> {reply, next_state}
      {:error, reason, next_state} -> {{:error, reason}, next_state}
    end
  end

  defp perform_capture_screenshot(state, opts) do
    format = Keyword.get(opts, :format, "png")
    quality = Keyword.get(opts, :quality, 90)

    state.native.capture_screenshot(state.runtime, state.current_page.id, format, quality)
  end

  defp perform_print_to_pdf(state, _opts) do
    state.native.print_to_pdf(state.runtime, state.current_page.id)
  end

  defp perform_click(state, locator, _opts) do
    state.native.click(state.runtime, state.current_page.id, selector(locator))
  end

  defp perform_fill(state, locator, value, _opts) do
    state.native.fill(state.runtime, state.current_page.id, selector(locator), value)
  end

  defp perform_wait_for(state, locator, opts) do
    state.native.wait_for(
      state.runtime,
      state.current_page.id,
      selector(locator),
      Keyword.get(opts, :timeout, 5_000)
    )
  end

  defp perform_select_option(state, locator, value, _opts) do
    state.native.select_option(state.runtime, state.current_page.id, selector(locator), value)
  end

  defp perform_hover(state, locator, _opts) do
    state.native.hover(state.runtime, state.current_page.id, selector(locator))
  end

  defp perform_get_text(state, locator, _opts) do
    state.native.get_text(state.runtime, state.current_page.id, selector(locator))
  end

  defp perform_get_attribute(state, locator, name, _opts) do
    state.native.get_attribute(state.runtime, state.current_page.id, selector(locator), name)
  end

  defp perform_set_cookie(state, cookie, opts) when is_map(cookie) do
    cookie_string = build_cookie_string(cookie, opts)
    state.native.set_cookie(state.runtime, state.current_page.id, cookie_string)
  end

  defp build_cookie_string(cookie, opts) do
    base = "#{Map.get(cookie, "name", "")}=#{Map.get(cookie, "value", "")}"
    domain = Map.get(cookie, "domain") || Keyword.get(opts, :domain)
    path = Map.get(cookie, "path") || Keyword.get(opts, :path)

    [base]
    |> append_cookie_part("domain", domain)
    |> append_cookie_part("path", path)
    |> Enum.join("; ")
  end

  defp append_cookie_part(parts, _key, nil), do: parts
  defp append_cookie_part(parts, _key, false), do: parts
  defp append_cookie_part(parts, key, value), do: parts ++ ["#{key}=#{value}"]

  defp navigate_to(state, event, url, opts \\ []) do
    telemetry_call(event, %{browser: self(), page_id: state.current_page.id, url: url}, fn ->
      do_navigate(state, url, opts)
    end)
  end

  defp do_navigate(state, url, opts) do
    case state.native.navigate(state.runtime, state.current_page.id, url) do
      {:ok, attrs} ->
        new_state = apply_navigation(state, page_ref(attrs), opts)
        {:ok, :ok, new_state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp apply_navigation(state, page, opts) do
    new_state = %{state | current_page: page}

    case Keyword.get(opts, :history_index) do
      nil -> new_state
      index -> %{new_state | history_index: index}
    end
  end

  defp history_url(state, index) when index >= 0 and index < length(state.history) do
    {:ok, Enum.at(state.history, index), index}
  end

  defp history_url(_state, _index), do: :error

  defp selector({:css, selector}) when is_binary(selector), do: selector
  defp selector(selector) when is_binary(selector), do: selector

  defp telemetry_span(event, metadata, fun) do
    Telemetry.span([:browser, event], metadata, fun, &telemetry_metadata/1)
  end

  defp telemetry_metadata({:ok, value}), do: Map.merge(%{status: :ok}, summarize_result(value))
  defp telemetry_metadata(:ok), do: %{status: :ok}
  defp telemetry_metadata({:error, reason}), do: %{status: :error, error: reason}
  defp telemetry_metadata({:stop, reason}), do: %{status: :error, error: reason}
  defp telemetry_metadata(other), do: Map.merge(%{status: :ok}, summarize_result(other))

  defp summarize_result(value) when is_binary(value),
    do: %{result: %{type: :binary, size: byte_size(value)}}

  defp summarize_result(value) when is_map(value),
    do: %{result: %{type: :map, size: map_size(value)}}

  defp summarize_result(value) when is_list(value),
    do: %{result: %{type: :list, size: length(value)}}

  defp summarize_result(value) when is_tuple(value),
    do: %{result: %{type: :tuple, size: tuple_size(value)}}

  defp summarize_result(value) when is_atom(value), do: %{result: %{type: :atom, value: value}}
  defp summarize_result(value), do: %{result: %{type: value}}
end
