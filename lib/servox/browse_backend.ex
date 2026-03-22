defmodule Servox.BrowseBackend do
  @moduledoc false

  @behaviour Browse.Browser

  alias Servox.Browser

  @impl Browse.Browser
  def init(opts) do
    opts
    |> Keyword.delete(:name)
    |> Browser.start_link()
  end

  @impl Browse.Browser
  def terminate(_reason, browser) when is_pid(browser) do
    GenServer.stop(browser, :normal)
    :ok
  catch
    :exit, _reason -> :ok
  end

  @impl Browse.Browser
  def navigate(browser, url, _opts) do
    Browser.navigate(browser, url)
  end

  @impl Browse.Browser
  def current_url(browser) do
    Browser.current_url(browser)
  end

  @impl Browse.Browser
  def content(browser) do
    Browser.content(browser)
  end

  @impl Browse.Browser
  def evaluate(browser, script, _opts) do
    Browser.evaluate(browser, script)
  end

  @impl Browse.Browser
  def capture_screenshot(browser, opts) do
    Browser.capture_screenshot(browser, opts)
  end

  @impl Browse.Browser
  def print_to_pdf(_browser, _opts), do: {:error, :unsupported}

  @impl Browse.Browser
  def click(_browser, _locator, _opts), do: {:error, :unsupported}

  @impl Browse.Browser
  def fill(_browser, _locator, _value, _opts), do: {:error, :unsupported}

  @impl Browse.Browser
  def wait_for(_browser, _locator, _opts), do: {:error, :unsupported}
end
