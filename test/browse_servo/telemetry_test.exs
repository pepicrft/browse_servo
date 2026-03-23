defmodule BrowseServo.TelemetryTest do
  use ExUnit.Case, async: false

  setup do
    pool = :"browse_servo_pool_#{System.unique_integer([:positive])}"

    start_supervised!(
      {BrowseServo.BrowserPool, name: pool, pool_size: 1, native_module: BrowseServo.TestNative}
    )

    handler_id = "browse_servo-telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:browse, :checkout, :start],
        [:browse, :checkout, :stop],
        [:browse_servo, :browser, :capture, :start],
        [:browse_servo, :browser, :capture, :stop]
      ],
      &__MODULE__.handle_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    {:ok, pool: pool}
  end

  def handle_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  test "checkout emits shared browse telemetry events", %{pool: pool} do
    assert {:ok, "https://example.com"} =
             BrowseServo.checkout(pool, fn browser ->
               :ok = BrowseServo.Browser.navigate(browser, "https://example.com")
               BrowseServo.Browser.current_url(browser)
             end)

    assert_receive {:telemetry_event, [:browse, :checkout, :start], %{system_time: system_time},
                    %{pool: ^pool, timeout: 30_000}},
                   1_000

    assert is_integer(system_time)

    assert_receive {:telemetry_event, [:browse, :checkout, :stop], %{duration: duration},
                    %{pool: ^pool, timeout: 30_000, status: :ok}},
                   1_000

    assert is_integer(duration)
    assert duration > 0
  end

  test "browser capture emits aligned telemetry events", %{pool: pool} do
    assert {:ok, <<137, 80, 78, 71>>} =
             BrowseServo.checkout(pool, fn browser ->
               result = BrowseServo.Browser.capture_screenshot(browser, format: "png", quality: 85)
               {result, :ok}
             end)

    assert_receive {:telemetry_event, [:browse_servo, :browser, :capture, :start],
                    %{system_time: _}, %{format: "png", quality: 85}},
                   1_000

    assert_receive {:telemetry_event, [:browse_servo, :browser, :capture, :stop],
                    %{duration: duration}, %{format: "png", quality: 85, status: :ok}},
                   1_000

    assert is_integer(duration)
    assert duration > 0
  end
end
