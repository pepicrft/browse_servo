defmodule Servox.BrowserTest do
  use ExUnit.Case, async: true

  alias Servox.Browser
  alias Servox.Page

  def handle_telemetry(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  setup do
    test_pid = self()
    handler_id = "servox-browser-test-#{System.unique_integer([:positive])}"

    events = [
      [:servox, :browser, :init, :start],
      [:servox, :browser, :init, :stop],
      [:servox, :browser, :navigate, :stop],
      [:servox, :browser, :new_page, :start],
      [:servox, :browser, :new_page, :stop],
      [:servox, :browser, :capture_screenshot, :stop],
      [:servox, :browser, :terminate]
    ]

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_telemetry/4,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "starts a browser and exposes capabilities" do
    assert {:ok, browser} = Browser.start_link(native_module: Servox.TestNative)

    assert_receive {:telemetry_event, [:servox, :browser, :init, :start], %{system_time: _},
                    %{native_module: _}}

    assert_receive {:telemetry_event, [:servox, :browser, :init, :stop], %{duration: _},
                    %{status: :ok}}

    assert Browser.capabilities(browser) ==
             {:ok,
              %{embedding: :rustler, engine: :servox, javascript: :planned, navigation: :direct}}
  end

  test "opens pages through the browser process" do
    assert {:ok, browser} = Browser.start_link(native_module: Servox.TestNative)

    assert {:ok, %Page{id: 1, url: "https://example.com"}} =
             Browser.new_page(browser, url: "https://example.com")

    assert_receive {:telemetry_event, [:servox, :browser, :new_page, :start], %{system_time: _},
                    %{url: "https://example.com"}}

    assert_receive {:telemetry_event, [:servox, :browser, :new_page, :stop], %{duration: _},
                    %{page_id: 1, status: :ok, url: "https://example.com"}}
  end

  test "supports browser-level navigation and screenshots" do
    assert {:ok, browser} = Browser.start_link(native_module: Servox.TestNative)

    assert :ok = Browser.navigate(browser, "https://example.com/docs")
    assert {:ok, "https://example.com/docs"} = Browser.current_url(browser)
    assert {:ok, "stub:jpeg:75"} = Browser.capture_screenshot(browser, format: "jpeg", quality: 75)

    assert_receive {:telemetry_event, [:servox, :browser, :navigate, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:servox, :browser, :capture_screenshot, :stop],
                    %{duration: _}, %{status: :ok}}
  end

  test "emits terminate telemetry when the browser stops" do
    assert {:ok, browser} = Browser.start_link(native_module: Servox.TestNative)
    ref = Process.monitor(browser)

    GenServer.stop(browser)

    assert_receive {:DOWN, ^ref, :process, ^browser, :normal}

    assert_receive {:telemetry_event, [:servox, :browser, :terminate], %{system_time: _},
                    %{browser: _}}
  end
end
