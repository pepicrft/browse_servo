defmodule ServoxTest do
  use ExUnit.Case, async: false

  alias Servox.BrowserPool

  setup do
    original_default_pool = Application.get_env(:servox, :default_pool)
    original_pools = Application.get_env(:servox, :pools)

    Application.put_env(:servox, :default_pool, :pool)

    Application.put_env(:servox, :pools,
      pool: [implementation: Servox.BrowseBackend, native_module: Servox.TestNative, pool_size: 1]
    )

    on_exit(fn ->
      if original_default_pool == nil do
        Application.delete_env(:servox, :default_pool)
      else
        Application.put_env(:servox, :default_pool, original_default_pool)
      end

      if original_pools == nil do
        Application.delete_env(:servox, :pools)
      else
        Application.put_env(:servox, :pools, original_pools)
      end
    end)

    :ok
  end

  test "children builds child specs from configured pools" do
    assert [%{id: :pool, start: {Browse, :start_link, [:pool, _opts]}}] = Servox.children()
  end

  test "browser pool delegates to Browse under the hood" do
    assert %{id: :pool} = BrowserPool.child_spec(:pool)
    assert {:ok, _pid} = BrowserPool.start_link(:pool)

    assert {:ok, "https://example.com"} =
             Servox.checkout(fn browser ->
               {:ok, page} = Servox.Browser.new_page(browser, url: "https://example.com")
               {:ok, page.url}
             end)
  end

  test "checkout supports explicit pools" do
    assert {:ok, _pid} = BrowserPool.start_link(:pool)

    assert {:ok, "https://example.com/docs"} =
             Servox.checkout(:pool, fn browser ->
               :ok = Servox.Browser.navigate(browser, "https://example.com/docs")
               Servox.Browser.current_url(browser)
             end)
  end
end
