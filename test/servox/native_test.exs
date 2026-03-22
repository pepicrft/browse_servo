defmodule Servox.NativeTest do
  use ExUnit.Case, async: true

  test "native runtime returns capabilities" do
    assert {:ok, runtime} = Servox.Native.new_runtime()
    assert {:ok, capabilities} = Servox.Native.capabilities(runtime)
    assert capabilities.engine == :servox
    assert capabilities.embedding == :rustler
    assert :ok = Servox.Native.shutdown(runtime)
  end

  test "native runtime manages page state" do
    assert {:ok, runtime} = Servox.Native.new_runtime()
    assert {:ok, page} = Servox.Native.open_page(runtime, "https://example.com")
    assert {:ok, "Page for https://example.com"} = Servox.Native.title(runtime, page.id)

    assert {:ok,
            "<html><head><title>Page for https://example.com</title></head><body><main data-url=\"https://example.com\"></main></body></html>"} =
             Servox.Native.content(runtime, page.id)

    assert {:ok, "Page for https://example.com"} =
             Servox.Native.evaluate(runtime, page.id, "document.title")

    assert :ok = Servox.Native.close_page(runtime, page.id)
    assert :ok = Servox.Native.shutdown(runtime)
  end
end
