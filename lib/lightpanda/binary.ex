defmodule Lightpanda.Binary do
  @moduledoc """
  Resolves and downloads the Lightpanda browser executable.
  """

  @github_api "https://api.github.com/repos/lightpanda-io/browser/releases/tags"

  @asset_names %{
    "aarch64-linux-gnu" => "lightpanda-aarch64-linux",
    "aarch64-macos-none" => "lightpanda-aarch64-macos",
    "x86_64-linux-gnu" => "lightpanda-x86_64-linux",
    "x86_64-macos-none" => "lightpanda-x86_64-macos"
  }

  @spec ensure_installed(keyword()) :: {:ok, String.t()} | {:error, term()}
  def ensure_installed(opts \\ []) do
    case Keyword.get(opts, :binary_path) do
      nil -> install_managed_binary(opts)
      binary_path -> {:ok, binary_path}
    end
  end

  @spec asset_name(String.t()) :: {:ok, String.t()} | {:error, term()}
  def asset_name(target) do
    case Map.fetch(@asset_names, target) do
      {:ok, name} -> {:ok, name}
      :error -> {:error, {:unsupported_target, target}}
    end
  end

  @spec cache_dir(keyword()) :: String.t()
  def cache_dir(opts \\ []) do
    Keyword.get_lazy(opts, :cache_dir, fn ->
      Path.join([
        System.user_home!(),
        ".cache",
        "lightpanda"
      ])
    end)
  end

  defp install_managed_binary(opts) do
    native = Application.get_env(:lightpanda, :native_module, Lightpanda.Native)

    release =
      Keyword.get(
        opts,
        :binary_release,
        Application.get_env(:lightpanda, :binary_release, "nightly")
      )

    target = native.target()

    with {:ok, asset_name} <- asset_name(target) do
      release_info = release_info(release, opts)
      asset = release_asset!(release_info, asset_name)
      destination = Path.join([cache_dir(opts), release, asset_name])

      File.mkdir_p!(Path.dirname(destination))

      if stale?(destination, digest(asset)) do
        http_module().download!(asset["browser_download_url"], destination, github_headers(opts))
        make_executable(destination, native.executable_mode())
      end

      {:ok, destination}
    end
  rescue
    error -> {:error, error}
  end

  defp release_info(release, opts) do
    "#{@github_api}/#{release}"
    |> http_module().get_json!(github_headers(opts))
  end

  defp release_asset!(release_info, asset_name) do
    Enum.find(release_info["assets"], &(&1["name"] == asset_name)) ||
      raise ArgumentError,
            "Lightpanda release does not include asset #{inspect(asset_name)}"
  end

  defp stale?(path, expected_digest) do
    cond do
      not File.exists?(path) ->
        true

      is_nil(expected_digest) ->
        false

      true ->
        digest = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
        digest != expected_digest
    end
  end

  defp digest(%{"digest" => "sha256:" <> digest}), do: String.downcase(digest)
  defp digest(_asset), do: nil

  defp make_executable(_path, 0), do: :ok
  defp make_executable(path, mode), do: File.chmod!(path, mode)

  defp github_headers(opts) do
    headers = [{"accept", "application/vnd.github+json"}]

    case Keyword.get(opts, :github_token) || System.get_env("GITHUB_TOKEN") do
      nil -> [headers: headers]
      token -> [headers: [{"authorization", "Bearer #{token}"} | headers]]
    end
  end

  defp http_module do
    Application.get_env(:lightpanda, :http_client, Lightpanda.HTTP)
  end
end
