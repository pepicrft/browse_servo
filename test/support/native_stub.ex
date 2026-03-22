defmodule Servox.TestNative do
  @moduledoc false

  def new_runtime, do: {:ok, :runtime}
  def shutdown(:runtime), do: :ok

  def capabilities(:runtime) do
    {:ok,
     %{
       engine: :servox,
       embedding: :rustler,
       javascript: :planned,
       navigation: :direct
     }}
  end

  def open_page(:runtime, url) do
    {:ok, %{id: 1, title: "Page for #{url}", url: url}}
  end

  def navigate(:runtime, page_id, url) do
    {:ok, %{id: page_id, title: "Page for #{url}", url: url}}
  end

  def content(:runtime, _page_id), do: {:ok, "<html><body>stub</body></html>"}
  def title(:runtime, _page_id), do: {:ok, "Stub Title"}
  def evaluate(:runtime, _page_id, "document.title"), do: {:ok, "Stub Title"}
  def evaluate(:runtime, _page_id, _expression), do: {:ok, :unsupported}

  def capture_screenshot(:runtime, _page_id, _format, _quality), do: {:error, :unsupported}

  def close_page(:runtime, _page_id), do: :ok
end
