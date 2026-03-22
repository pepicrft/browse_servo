defmodule Lightpanda.CLITest do
  use ExUnit.Case, async: true
  use Mimic

  alias Lightpanda.CLI

  setup do
    verify_on_exit!()
    Application.put_env(:lightpanda, :runner, Lightpanda.Runner)
    :ok
  end

  test "fetch returns a structured result" do
    expect(Lightpanda.Runner, :command, fn "/tmp/lightpanda",
                                           ["fetch", "https://example.com"],
                                           _opts ->
      {"<html></html>", 0}
    end)

    assert {:ok, result} =
             CLI.fetch("https://example.com", binary_path: "/tmp/lightpanda")

    assert result.output == "<html></html>"
    assert result.binary_path == "/tmp/lightpanda"
  end

  test "version trims stdout" do
    expect(Lightpanda.Runner, :command, fn "/tmp/lightpanda", ["version"], _opts ->
      {"0.1.0\n", 0}
    end)

    assert CLI.version(binary_path: "/tmp/lightpanda") == {:ok, "0.1.0"}
  end
end
