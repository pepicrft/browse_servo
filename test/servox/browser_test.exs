defmodule Servox.BrowserTest do
  use ExUnit.Case, async: true

  alias Servox.Browser
  alias Servox.Page

  test "starts a browser and exposes capabilities" do
    assert {:ok, browser} = Browser.start_link(native_module: Servox.TestNative)

    assert Browser.capabilities(browser) ==
             {:ok,
              %{embedding: :rustler, engine: :servox, javascript: :planned, navigation: :direct}}
  end

  test "opens pages through the browser process" do
    assert {:ok, browser} = Browser.start_link(native_module: Servox.TestNative)

    assert {:ok, %Page{id: 1, url: "https://example.com"}} =
             Browser.new_page(browser, url: "https://example.com")
  end
end
