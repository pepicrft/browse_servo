defmodule Lightpanda.Page do
  @moduledoc """
  High-level page API built on top of the CDP connection.
  """

  alias Lightpanda.CDP.Client

  @enforce_keys [:browser, :client, :session_id, :target_id]
  defstruct [:browser, :client, :context_id, :session_id, :target_id]

  @type t :: %__MODULE__{
          browser: pid(),
          client: pid(),
          context_id: String.t() | nil,
          session_id: String.t(),
          target_id: String.t()
        }

  @doc """
  Navigates the page to `url`.
  """
  @spec goto(t(), String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def goto(%__MODULE__{} = page, url, opts \\ []) when is_binary(url) do
    with {:ok, _result} <-
           Client.command(page.client, "Page.navigate", %{"url" => url},
             session_id: page.session_id
           ),
         {:ok, _page} <- wait(page, opts) do
      {:ok, page}
    end
  end

  @doc """
  Waits for the requested page lifecycle point.
  """
  @spec wait(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def wait(%__MODULE__{} = page, opts \\ []) do
    wait_until = Keyword.get(opts, :wait_until, :load)
    timeout = Keyword.get(opts, :timeout, Application.get_env(:lightpanda, :cdp_timeout, 5_000))
    Client.subscribe(page.client)

    case wait_until do
      :fixed ->
        Process.sleep(Keyword.get(opts, :wait_ms, 250))
        {:ok, page}

      :domcontentloaded ->
        receive_event(page, "Page.domContentEventFired", timeout)

      :networkidle ->
        receive_network_idle(page, timeout)

      _ ->
        receive_event(page, "Page.loadEventFired", timeout)
    end
  after
    Client.unsubscribe(page.client)
  end

  @doc """
  Returns the fully rendered outer HTML.
  """
  @spec content(t()) :: {:ok, String.t()} | {:error, term()}
  def content(%__MODULE__{} = page) do
    with {:ok, %{"root" => %{"nodeId" => node_id}}} <-
           Client.command(page.client, "DOM.getDocument", %{}, session_id: page.session_id),
         {:ok, %{"outerHTML" => html}} <-
           Client.command(
             page.client,
             "DOM.getOuterHTML",
             %{"nodeId" => node_id},
             session_id: page.session_id
           ) do
      {:ok, html}
    end
  end

  @doc """
  Evaluates JavaScript in the current page and returns the by-value result.
  """
  @spec evaluate(t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def evaluate(%__MODULE__{} = page, expression, opts \\ []) when is_binary(expression) do
    params = %{
      "awaitPromise" => true,
      "expression" => expression,
      "returnByValue" => Keyword.get(opts, :return_by_value, true)
    }

    with {:ok, %{"result" => result}} <-
           Client.command(page.client, "Runtime.evaluate", params, session_id: page.session_id) do
      {:ok, unwrap_result(result)}
    end
  end

  @doc """
  Clicks the first DOM node matching `selector`.
  """
  @spec click(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def click(%__MODULE__{} = page, selector) when is_binary(selector) do
    script = """
    (() => {
      const selector = #{Jason.encode!(selector)};
      const node = document.querySelector(selector);
      if (!node) throw new Error(`missing selector: ${selector}`);
      node.click();
      return true;
    })()
    """

    with {:ok, true} <- evaluate(page, script) do
      {:ok, page}
    end
  end

  @doc """
  Fills the first form field matching `selector` with `value`.
  """
  @spec fill(t(), String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def fill(%__MODULE__{} = page, selector, value) when is_binary(selector) and is_binary(value) do
    script = """
    (() => {
      const selector = #{Jason.encode!(selector)};
      const value = #{Jason.encode!(value)};
      const node = document.querySelector(selector);
      if (!node) throw new Error(`missing selector: ${selector}`);
      node.focus();
      node.value = value;
      node.dispatchEvent(new Event("input", { bubbles: true }));
      node.dispatchEvent(new Event("change", { bubbles: true }));
      return true;
    })()
    """

    with {:ok, true} <- evaluate(page, script) do
      {:ok, page}
    end
  end

  @doc """
  Returns `textContent` for the first node matching `selector`.
  """
  @spec text(t(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def text(%__MODULE__{} = page, selector) when is_binary(selector) do
    selector
    |> selector_expression("textContent")
    |> then(&evaluate(page, &1))
  end

  @doc """
  Returns `innerHTML` for the first node matching `selector`.
  """
  @spec html(t(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def html(%__MODULE__{} = page, selector) when is_binary(selector) do
    selector
    |> selector_expression("innerHTML")
    |> then(&evaluate(page, &1))
  end

  @doc """
  Returns all cookies visible to the current page.
  """
  @spec cookies(t()) :: {:ok, [map()]} | {:error, term()}
  def cookies(%__MODULE__{} = page) do
    with {:ok, %{"cookies" => cookies}} <-
           Client.command(page.client, "Network.getAllCookies", %{}, session_id: page.session_id) do
      {:ok, cookies}
    end
  end

  @doc """
  Sets cookies for the current page session.
  """
  @spec set_cookies(t(), [map()]) :: {:ok, t()} | {:error, term()}
  def set_cookies(%__MODULE__{} = page, cookies) when is_list(cookies) do
    with {:ok, _result} <-
           Client.command(
             page.client,
             "Network.setCookies",
             %{"cookies" => cookies},
             session_id: page.session_id
           ) do
      {:ok, page}
    end
  end

  @doc """
  Sets extra HTTP headers for future requests.
  """
  @spec set_extra_http_headers(t(), map()) :: {:ok, t()} | {:error, term()}
  def set_extra_http_headers(%__MODULE__{} = page, headers) when is_map(headers) do
    with {:ok, _result} <-
           Client.command(
             page.client,
             "Network.setExtraHTTPHeaders",
             %{"headers" => headers},
             session_id: page.session_id
           ) do
      {:ok, page}
    end
  end

  @doc """
  Enables Fetch-domain request interception.
  """
  @spec enable_request_interception(t(), [map()]) :: {:ok, t()} | {:error, term()}
  def enable_request_interception(%__MODULE__{} = page, patterns \\ [%{}]) do
    params = %{"patterns" => patterns}

    with {:ok, _result} <-
           Client.command(page.client, "Fetch.enable", params, session_id: page.session_id) do
      {:ok, page}
    end
  end

  @doc """
  Continues an intercepted request.
  """
  @spec continue_request(t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def continue_request(%__MODULE__{} = page, request_id, opts \\ []) when is_binary(request_id) do
    params =
      %{"requestId" => request_id}
      |> maybe_put("headers", Keyword.get(opts, :headers))
      |> maybe_put("method", Keyword.get(opts, :method))
      |> maybe_put("postData", Keyword.get(opts, :post_data))
      |> maybe_put("url", Keyword.get(opts, :url))

    Client.command(page.client, "Fetch.continueRequest", params, session_id: page.session_id)
  end

  @doc """
  Fails an intercepted request.
  """
  @spec fail_request(t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def fail_request(%__MODULE__{} = page, request_id, error_reason \\ "Failed")
      when is_binary(request_id) and is_binary(error_reason) do
    params = %{"requestId" => request_id, "errorReason" => error_reason}
    Client.command(page.client, "Fetch.failRequest", params, session_id: page.session_id)
  end

  @doc """
  Fulfills an intercepted request.
  """
  @spec fulfill_request(t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fulfill_request(%__MODULE__{} = page, request_id, opts)
      when is_binary(request_id) and is_list(opts) do
    params =
      %{
        "requestId" => request_id,
        "responseCode" => Keyword.get(opts, :status, 200)
      }
      |> maybe_put("body", Keyword.get(opts, :body))
      |> maybe_put("responseHeaders", Keyword.get(opts, :headers))

    Client.command(page.client, "Fetch.fulfillRequest", params, session_id: page.session_id)
  end

  @doc """
  Closes the page target.
  """
  @spec close(t()) :: {:ok, map()} | {:error, term()}
  def close(%__MODULE__{} = page) do
    Client.command(page.client, "Target.closeTarget", %{"targetId" => page.target_id})
  end

  defp selector_expression(selector, property) do
    """
    (() => {
      const node = document.querySelector(#{Jason.encode!(selector)});
      return node ? node.#{property} : null;
    })()
    """
  end

  defp unwrap_result(%{"value" => value}), do: value
  defp unwrap_result(result), do: result

  defp receive_event(page, method, timeout) do
    session_id = page.session_id

    receive do
      {:lightpanda_cdp_event, ^method, _params, ^session_id} -> {:ok, page}
    after
      timeout -> {:error, {:timeout, method}}
    end
  end

  defp receive_network_idle(page, timeout) do
    session_id = page.session_id

    receive do
      {:lightpanda_cdp_event, "Page.lifecycleEvent", %{"name" => "networkIdle"}, ^session_id} ->
        {:ok, page}
    after
      timeout -> {:error, {:timeout, :networkidle}}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
