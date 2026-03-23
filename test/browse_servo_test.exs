defmodule BrowseServoTest do
  use ExUnit.Case, async: false

  alias BrowseServo.BrowserPool

  setup do
    original_default_pool = Application.get_env(:browse_servo, :default_pool)
    original_pools = Application.get_env(:browse_servo, :pools)

    Application.put_env(:browse_servo, :default_pool, :pool)

    Application.put_env(:browse_servo, :pools,
      pool: [
        implementation: BrowseServo.BrowseBackend,
        native_module: BrowseServo.TestNative,
        pool_size: 1
      ]
    )

    on_exit(fn ->
      if original_default_pool == nil do
        Application.delete_env(:browse_servo, :default_pool)
      else
        Application.put_env(:browse_servo, :default_pool, original_default_pool)
      end

      if original_pools == nil do
        Application.delete_env(:browse_servo, :pools)
      else
        Application.put_env(:browse_servo, :pools, original_pools)
      end
    end)

    :ok
  end

  test "children builds child specs from configured pools" do
    assert [%{id: :pool, start: {Browse, :start_link, [:pool, _opts]}}] = BrowseServo.children()
  end

  test "browser pool delegates to Browse under the hood" do
    assert %{id: :pool} = BrowserPool.child_spec(:pool)
    assert {:ok, _pid} = BrowserPool.start_link(:pool)

    assert {:ok, "https://example.com"} =
             BrowseServo.checkout(fn browser ->
               :ok = BrowseServo.Browser.navigate(browser, "https://example.com")
               BrowseServo.Browser.current_url(browser)
             end)
  end

  test "checkout supports explicit pools" do
    assert {:ok, _pid} = BrowserPool.start_link(:pool)

    assert {:ok, "https://example.com/docs"} =
             BrowseServo.checkout(:pool, fn browser ->
               :ok = BrowseServo.Browser.navigate(browser, "https://example.com/docs")
               BrowseServo.Browser.current_url(browser)
             end)
  end
end
