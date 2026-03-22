defmodule Lightpanda.CommandTest do
  use ExUnit.Case, async: true

  alias Lightpanda.Command

  test "builds fetch arguments" do
    assert Command.fetch("https://example.com",
             dump: :html,
             obey_robots: true,
             strip_mode: [:js, :css],
             wait_until: :networkidle
           ) == [
             "fetch",
             "--obey_robots",
             "--dump",
             "html",
             "--strip_mode",
             "js,css",
             "--wait_until",
             "networkidle",
             "https://example.com"
           ]
  end

  test "builds serve arguments" do
    assert Command.serve(host: "127.0.0.1", port: 9222, log_level: :info) == [
             "serve",
             "--log_level",
             "info",
             "--host",
             "127.0.0.1",
             "--port",
             "9222"
           ]
  end
end
