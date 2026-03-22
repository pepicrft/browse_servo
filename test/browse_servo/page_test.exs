defmodule BrowseServo.PageTest do
  use ExUnit.Case, async: true

  alias BrowseServo.Browser
  alias BrowseServo.Page

  setup do
    {:ok, browser} =
      Browser.start_link(
        native_module: BrowseServo.TestNative,
        screenshot_module: BrowseServo.TestScreenshot
      )

    {:ok, page} = Browser.new_page(browser, url: "https://example.com")
    %{page: page}
  end

  test "delegates navigation through the browser owner", %{page: page} do
    assert {:ok, %Page{url: "https://example.com/docs"}} =
             Page.goto(page, "https://example.com/docs")
  end

  test "reads title and content", %{page: page} do
    assert Page.title(page) == {:ok, "Stub Title"}
    assert Page.content(page) == {:ok, "<html><body>stub</body></html>"}
  end

  test "evaluates expressions", %{page: page} do
    assert Page.evaluate(page, "document.title") == {:ok, "Stub Title"}
  end

  test "closes pages", %{page: page} do
    assert Page.close(page) == :ok
  end
end
