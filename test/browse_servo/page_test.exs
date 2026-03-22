defmodule BrowseServo.PageTest do
  use ExUnit.Case, async: true

  alias BrowseServo.Browser
  alias BrowseServo.Page

  setup do
    {:ok, browser} = Browser.start_link(native_module: BrowseServo.TestNative)

    {:ok, page} = Browser.new_page(browser, url: "https://example.com")
    %{page: page}
  end

  test "delegates navigation through the browser owner", %{page: page} do
    assert {:ok, %Page{url: "https://example.com/docs"}} =
             Page.goto(page, "https://example.com/docs")
  end

  test "reads title and content", %{page: page} do
    assert Page.title(page) == {:ok, "Example Title"}

    assert Page.content(page) ==
             {:ok, "<html><body><main data-testid=\"content\">content</main></body></html>"}
  end

  test "evaluates expressions", %{page: page} do
    assert Page.evaluate(page, "document.title") == {:ok, "document.title"}
  end

  test "closes pages", %{page: page} do
    assert Page.close(page) == :ok
  end
end
