defmodule BrowseServo.BrowserTest do
  use ExUnit.Case, async: true

  alias BrowseServo.Browser

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
      [:browse_servo, :browser, :capture, :stop],
      [:browse_servo, :browser, :print_to_pdf, :stop],
      [:browse_servo, :browser, :click, :stop],
      [:browse_servo, :browser, :fill, :stop],
      [:browse_servo, :browser, :wait_for, :stop],
      [:browse_servo, :browser, :title, :stop],
      [:browse_servo, :browser, :go_back, :stop],
      [:browse_servo, :browser, :go_forward, :stop],
      [:browse_servo, :browser, :reload, :stop],
      [:browse_servo, :browser, :select_option, :stop],
      [:browse_servo, :browser, :hover, :stop],
      [:browse_servo, :browser, :get_text, :stop],
      [:browse_servo, :browser, :get_attribute, :stop],
      [:browse_servo, :browser, :get_cookies, :stop],
      [:browse_servo, :browser, :set_cookie, :stop],
      [:browse_servo, :browser, :clear_cookies, :stop],
      [:browse_servo, :browser, :terminate]
    ]

    :ok = :telemetry.attach_many(handler_id, events, &__MODULE__.handle_telemetry/4, test_pid)
    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "starts a browser runtime" do
    assert {:ok, browser} = Browser.start_link(native_module: BrowseServo.TestNative)

    assert_receive {:telemetry_event, [:browse_servo, :browser, :init, :start], %{system_time: _},
                    %{native_module: _}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :init, :stop], %{duration: _},
                    %{status: :ok}}

    assert {:ok, "about:blank"} = Browser.current_url(browser)
  end

  test "supports the browse browser contract" do
    assert {:ok, browser} = Browser.start_link(native_module: BrowseServo.TestNative)

    assert :ok = Browser.navigate(browser, "https://example.com/form")
    assert {:ok, "https://example.com/form"} = Browser.current_url(browser)

    assert {:ok, "<html><body><main data-testid=\"content\">content</main></body></html>"} =
             Browser.content(browser)

    assert {:ok, "document.title"} = Browser.evaluate(browser, "document.title")

    assert {:ok, <<137, 80, 78, 71>>} =
             Browser.capture_screenshot(browser, width: 1440, height: 900)

    assert {:ok, <<37, 80, 68, 70>>} = Browser.print_to_pdf(browser)
    assert :ok = Browser.click(browser, "#submit")
    assert :ok = Browser.fill(browser, "#email", "user@example.com")
    assert :ok = Browser.wait_for(browser, "#done", timeout: 1_000)

    assert {:ok, "Example Title"} = Browser.title(browser)
    assert :ok = Browser.select_option(browser, "#choice", "beta")
    assert :ok = Browser.hover(browser, "#hover-target")
    assert {:ok, "mock text"} = Browser.get_text(browser, "#content")
    assert {:ok, "mock-value"} = Browser.get_attribute(browser, "#content", "data-kind")

    assert_receive {:telemetry_event, [:browse_servo, :browser, :navigate, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :capture, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :print_to_pdf, :stop],
                    %{duration: _}, %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :click, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :fill, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :wait_for, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :title, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :select_option, :stop],
                    %{duration: _}, %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :hover, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :get_text, :stop], %{duration: _},
                    %{status: :ok}}

    assert_receive {:telemetry_event, [:browse_servo, :browser, :get_attribute, :stop],
                    %{duration: _}, %{status: :ok}}
  end

  test "supports navigation history" do
    assert {:ok, browser} = Browser.start_link(native_module: BrowseServo.TestNative)

    assert :ok = Browser.navigate(browser, "https://example.com/page-1")
    assert {:ok, "https://example.com/page-1"} = Browser.current_url(browser)

    assert :ok = Browser.navigate(browser, "https://example.com/page-2")
    assert {:ok, "https://example.com/page-2"} = Browser.current_url(browser)

    assert :ok = Browser.go_back(browser)
    assert {:ok, "https://example.com/page-1"} = Browser.current_url(browser)

    assert :ok = Browser.go_forward(browser)
    assert {:ok, "https://example.com/page-2"} = Browser.current_url(browser)

    assert :ok = Browser.reload(browser)
    assert {:ok, "https://example.com/page-2"} = Browser.current_url(browser)

    assert {:error, :navigation_history_unavailable} = Browser.go_forward(browser)
  end

  test "manages cookies" do
    assert {:ok, browser} = Browser.start_link(native_module: BrowseServo.TestNative)

    assert :ok = Browser.set_cookie(browser, %{"name" => "session", "value" => "abc123"})
    assert {:ok, _cookies} = Browser.get_cookies(browser)
    assert :ok = Browser.clear_cookies(browser)
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
