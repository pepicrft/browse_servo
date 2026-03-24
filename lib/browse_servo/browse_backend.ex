defmodule BrowseServo.BrowseBackend do
  @moduledoc false

  @behaviour Browse.Browser

  alias BrowseServo.Browser

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
  def print_to_pdf(browser, opts) do
    Browser.print_to_pdf(browser, opts)
  end

  @impl Browse.Browser
  def click(browser, locator, opts) do
    Browser.click(browser, locator, opts)
  end

  @impl Browse.Browser
  def fill(browser, locator, value, opts) do
    Browser.fill(browser, locator, value, opts)
  end

  @impl Browse.Browser
  def wait_for(browser, locator, opts) do
    Browser.wait_for(browser, locator, opts)
  end

  @impl Browse.Browser
  def title(browser) do
    Browser.title(browser)
  end

  @impl Browse.Browser
  def go_back(browser, _opts) do
    Browser.go_back(browser)
  end

  @impl Browse.Browser
  def go_forward(browser, _opts) do
    Browser.go_forward(browser)
  end

  @impl Browse.Browser
  def reload(browser, _opts) do
    Browser.reload(browser)
  end

  @impl Browse.Browser
  def select_option(browser, locator, value, opts) do
    Browser.select_option(browser, locator, value, opts)
  end

  @impl Browse.Browser
  def hover(browser, locator, opts) do
    Browser.hover(browser, locator, opts)
  end

  @impl Browse.Browser
  def get_text(browser, locator, opts) do
    Browser.get_text(browser, locator, opts)
  end

  @impl Browse.Browser
  def get_attribute(browser, locator, name, opts) do
    Browser.get_attribute(browser, locator, name, opts)
  end

  @impl Browse.Browser
  def get_cookies(browser, _opts) do
    Browser.get_cookies(browser)
  end

  @impl Browse.Browser
  def set_cookie(browser, cookie, opts) do
    Browser.set_cookie(browser, cookie, opts)
  end

  @impl Browse.Browser
  def clear_cookies(browser, _opts) do
    Browser.clear_cookies(browser)
  end
end
