defmodule Servox.Native.Release do
  @moduledoc false

  def base_url(version) do
    "https://github.com/pepicrft/servox/releases/download/v#{version}"
  end
end

defmodule Servox.Native do
  @moduledoc false

  use RustlerPrecompiled,
    otp_app: :servox,
    crate: "servox_native",
    base_url: {Servox.Native.Release, :base_url},
    force_build: System.get_env("SERVOX_BUILD") in ["1", "true"],
    version: Mix.Project.config()[:version]

  def new_runtime, do: :erlang.nif_error(:nif_not_loaded)
  def shutdown(_runtime), do: :erlang.nif_error(:nif_not_loaded)
  def capabilities(_runtime), do: :erlang.nif_error(:nif_not_loaded)
  def open_page(_runtime, _url), do: :erlang.nif_error(:nif_not_loaded)
  def navigate(_runtime, _page_id, _url), do: :erlang.nif_error(:nif_not_loaded)
  def content(_runtime, _page_id), do: :erlang.nif_error(:nif_not_loaded)
  def title(_runtime, _page_id), do: :erlang.nif_error(:nif_not_loaded)
  def evaluate(_runtime, _page_id, _expression), do: :erlang.nif_error(:nif_not_loaded)

  def capture_screenshot(_runtime, _page_id, _format, _quality),
    do: :erlang.nif_error(:nif_not_loaded)

  def close_page(_runtime, _page_id), do: :erlang.nif_error(:nif_not_loaded)
end
