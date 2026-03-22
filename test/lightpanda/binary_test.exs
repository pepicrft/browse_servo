defmodule Lightpanda.BinaryTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Lightpanda.Binary

  setup do
    verify_on_exit!()
    Application.put_env(:lightpanda, :http_client, Lightpanda.HTTP)
    Application.put_env(:lightpanda, :native_module, Lightpanda.TestNative)
    :ok
  end

  test "maps supported target to release asset" do
    assert Binary.asset_name("aarch64-macos-none") == {:ok, "lightpanda-aarch64-macos"}
  end

  test "downloads and chmods a managed binary" do
    cache_dir =
      Path.join(System.tmp_dir!(), "lightpanda-test-#{System.unique_integer([:positive])}")

    expect(Lightpanda.HTTP, :get_json!, fn _url, _opts ->
      %{
        "assets" => [
          %{
            "browser_download_url" => "https://example.test/lightpanda",
            "digest" => "sha256:" <> Base.encode16(:crypto.hash(:sha256, "binary"), case: :lower),
            "name" => "lightpanda-aarch64-macos"
          }
        ]
      }
    end)

    expect(Lightpanda.HTTP, :download!, fn _url, path, _opts ->
      File.write!(path, "binary")
      :ok
    end)

    assert {:ok, path} = Binary.ensure_installed(cache_dir: cache_dir)
    assert File.read!(path) == "binary"
  end
end
