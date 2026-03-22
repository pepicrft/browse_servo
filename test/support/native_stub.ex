defmodule Lightpanda.TestNative do
  @moduledoc false

  def target, do: "aarch64-macos-none"
  def executable_mode, do: 0o755
end
