defmodule BrowseServo.BrowserTest do
  use ExUnit.Case, async: true

  alias BrowseServo.Browser
  alias BrowseServo.Page

  def handle_telemetry(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  setup do
    test_pid = self()
    handler_id = "browse_servo-browser-test-#{System.unique_integer([:positive])}"

    events = [
      [:browse_servo, :browser, :init, :start],
      [:browse_servo, :browser, :init, :stop],
      [:browse_servo, :browser, :navigate, :stop],
      [:browse_servo, :browser, :new_page, :start],
      [:browse_servo, :browser, :new_page, :stop],
      [:browse_servo, :browser, :capture, :stop],
      [:browse_servo, :browser, :print_to_pdf, :stop],
      [:browse_servo, :browser, :click, :stop],
      [:browse_servo, :browser, :fill, :stop],
      [:browse_servo, :browser, :wait_for, :stop],
      [:browse_servo, :browser, :terminate]
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
    assert {:ok, browser} =
             Browser.start_link(native_module: BrowseServo.TestNative)

    assert_receive {:telemetry_event, [:browse_servo, :browser, :init, :start], %{system_time: _},
                    %{native_module: _}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :init, :stop], %{duration: _},
                    %{status: :ok}}

    assert Browser.capabilities(browser) ==
             {:ok,
              %{
                embedding: :rustler,
                engine: :browse_servo,
                javascript: :supported,
                navigation: :direct
              }}
  end

  test "opens pages through the browser process" do
    assert {:ok, browser} =
             Browser.start_link(native_module: BrowseServo.TestNative)

    assert {:ok, %Page{id: 1, url: "https://example.com"}} =
             Browser.new_page(browser, url: "https://example.com")

    assert_receive {:telemetry_event, [:browse_servo, :browser, :new_page, :start],
                    %{system_time: _}, %{url: "https://example.com"}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :new_page, :stop], %{duration: _},
                    %{page_id: 1, status: :ok, url: "https://example.com"}}
  end

  test "supports browser-level navigation and screenshots" do
    assert {:ok, browser} = Browser.start_link(native_module: BrowseServo.TestNative)

    assert :ok = Browser.navigate(browser, "https://example.com/docs")
    assert {:ok, "https://example.com/docs"} = Browser.current_url(browser)

    assert {:ok, <<137, 80, 78, 71>>} =
             Browser.capture_screenshot(browser, width: 1440, height: 900)

    assert_receive {:telemetry_event, [:browse_servo, :browser, :navigate, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :capture, :stop], %{duration: _},
                    %{status: :ok}}
  end

  test "supports pdf output and browser actions" do
    assert {:ok, browser} = Browser.start_link(native_module: BrowseServo.TestNative)

    assert :ok = Browser.navigate(browser, "https://example.com/form")
    assert :ok = Browser.click(browser, "#submit")
    assert :ok = Browser.fill(browser, "#email", "user@example.com")
    assert :ok = Browser.wait_for(browser, "#done", timeout: 1_000)
    assert {:ok, <<37, 80, 68, 70>>} = Browser.print_to_pdf(browser)

    assert_receive {:telemetry_event, [:browse_servo, :browser, :click, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :fill, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :wait_for, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :print_to_pdf, :stop],
                    %{duration: _}, %{status: :ok}}
  end

  test "emits terminate telemetry when the browser stops" do
    assert {:ok, browser} = Browser.start_link(native_module: BrowseServo.TestNative)

    ref = Process.monitor(browser)

    GenServer.stop(browser)

    assert_receive {:DOWN, ^ref, :process, ^browser, :normal}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :terminate], %{system_time: _},
                    %{browser: _}}
  end
end
