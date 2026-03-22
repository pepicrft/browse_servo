defmodule BrowseServo.NativeTest do
  use ExUnit.Case, async: true

  test "native runtime returns capabilities" do
    assert {:ok, runtime} = BrowseServo.Native.new_runtime()
    assert {:ok, capabilities} = BrowseServo.Native.capabilities(runtime)
    assert capabilities.engine == :browse_servo
    assert capabilities.embedding == :rustler
    assert :ok = BrowseServo.Native.shutdown(runtime)
  end

  test "native runtime manages page state" do
    assert {:ok, runtime} = BrowseServo.Native.new_runtime()
    assert {:ok, page} = BrowseServo.Native.open_page(runtime, "https://example.com")
    assert {:ok, "Page for https://example.com"} = BrowseServo.Native.title(runtime, page.id)

    assert {:ok,
            "<html><head><title>Page for https://example.com</title></head><body><main data-url=\"https://example.com\"></main></body></html>"} =
             BrowseServo.Native.content(runtime, page.id)

    assert {:ok, "Page for https://example.com"} =
             BrowseServo.Native.evaluate(runtime, page.id, "document.title")

    assert :ok = BrowseServo.Native.close_page(runtime, page.id)
    assert :ok = BrowseServo.Native.shutdown(runtime)
  end
end
