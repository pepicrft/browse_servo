defmodule Lightpanda.Native do
  @moduledoc false

  use ZiglerPrecompiled,
    otp_app: :lightpanda,
    base_url: "https://github.com/pepicrft/lightpanda/releases/download/v0.1.0-dev",
    version: "0.1.0-dev",
    zig_code_path: "./native/lightpanda_native.zig",
    nifs: [target: 0, executable_mode: 0]

  @version "0.1.0-dev"
end
