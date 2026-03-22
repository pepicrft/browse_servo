defmodule Servox.TestScreenshot do
  @moduledoc false

  def capture(url, opts) do
    width = Keyword.get(opts, :width, 1280)
    height = Keyword.get(opts, :height, 720)
    {:ok, "screenshot:#{url}:#{width}x#{height}"}
  end
end
