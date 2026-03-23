defmodule BrowseServo.TestNative do
  @moduledoc false

  def new_runtime, do: {:ok, :runtime}
  def shutdown(:runtime), do: :ok

  def capabilities(:runtime) do
    {:ok,
     %{
       engine: :browse_servo,
       embedding: :rustler,
       javascript: :supported,
       navigation: :direct
     }}
  end

  def open_page(:runtime, url) do
    {:ok, %{id: 1, title: "Page for #{url}", url: url}}
  end

  def navigate(:runtime, page_id, url) do
    {:ok, %{id: page_id, title: "Page for #{url}", url: url}}
  end

  def content(:runtime, _page_id),
    do: {:ok, "<html><body><main data-testid=\"content\">content</main></body></html>"}

  def title(:runtime, _page_id), do: {:ok, "Example Title"}
  def evaluate(:runtime, _page_id, expression), do: {:ok, expression}

  def capture_screenshot(:runtime, _page_id, _format, _quality), do: {:ok, <<137, 80, 78, 71>>}
  def print_to_pdf(:runtime, _page_id), do: {:ok, <<37, 80, 68, 70>>}
  def click(:runtime, _page_id, _selector), do: :ok
  def fill(:runtime, _page_id, _selector, _value), do: :ok
  def wait_for(:runtime, _page_id, _selector, _timeout_ms), do: :ok

  def close_page(:runtime, _page_id), do: :ok
end
