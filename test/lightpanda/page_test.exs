defmodule Lightpanda.PageTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Lightpanda.Page

  setup do
    verify_on_exit!()

    page = %Page{
      browser: self(),
      client: self(),
      context_id: nil,
      session_id: "session-1",
      target_id: "target-1"
    }

    %{page: page}
  end

  test "evaluate unwraps by-value runtime results", %{page: page} do
    expect(Lightpanda.CDP.Client, :command, fn _client, "Runtime.evaluate", params, opts ->
      assert params["returnByValue"]
      assert opts[:session_id] == "session-1"
      {:ok, %{"result" => %{"value" => "Example"}}}
    end)

    assert Page.evaluate(page, "document.title") == {:ok, "Example"}
  end

  test "click delegates through runtime evaluate", %{page: page} do
    expect(Lightpanda.CDP.Client, :command, fn _client, "Runtime.evaluate", _params, _opts ->
      {:ok, %{"result" => %{"value" => true}}}
    end)

    assert Page.click(page, "button[type=submit]") == {:ok, page}
  end

  test "content resolves the DOM root and outer HTML", %{page: page} do
    expect(Lightpanda.CDP.Client, :command, 2, fn
      _client, "DOM.getDocument", %{}, _opts ->
        {:ok, %{"root" => %{"nodeId" => 1}}}

      _client, "DOM.getOuterHTML", %{"nodeId" => 1}, _opts ->
        {:ok, %{"outerHTML" => "<html></html>"}}
    end)

    assert Page.content(page) == {:ok, "<html></html>"}
  end

  test "request interception helpers use the Fetch domain", %{page: page} do
    expect(Lightpanda.CDP.Client, :command, 2, fn
      _client, "Fetch.enable", %{"patterns" => [%{}]}, _opts ->
        {:ok, %{}}

      _client, "Fetch.continueRequest", %{"requestId" => "req-1"}, _opts ->
        {:ok, %{}}
    end)

    assert Page.enable_request_interception(page) == {:ok, page}
    assert Page.continue_request(page, "req-1") == {:ok, %{}}
  end
end
