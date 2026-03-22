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

  def navigate(:runtime, 1, url) do
    {:ok, %{id: 1, title: "Page for #{url}", url: url}}
  end

  def content(:runtime, 1), do: {:ok, "<html><body>stub</body></html>"}
  def title(:runtime, 1), do: {:ok, "Stub Title"}
  def evaluate(:runtime, 1, "document.title"), do: {:ok, "Stub Title"}
  def evaluate(:runtime, 1, _expression), do: {:ok, :unsupported}
  def close_page(:runtime, 1), do: :ok
end
