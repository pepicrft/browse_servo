defmodule Servox.Native do
  @moduledoc false

  use RustlerPrecompiled,
    otp_app: :servox,
    crate: "servox_native",
    base_url: "https://github.com/pepicrft/servox/releases/download/v0.1.0-dev",
    force_build: System.get_env("SERVOX_BUILD") in ["1", "true"],
    version: "0.1.0-dev"

  def new_runtime, do: :erlang.nif_error(:nif_not_loaded)
  def shutdown(_runtime), do: :erlang.nif_error(:nif_not_loaded)
  def capabilities(_runtime), do: :erlang.nif_error(:nif_not_loaded)
  def open_page(_runtime, _url), do: :erlang.nif_error(:nif_not_loaded)
  def navigate(_runtime, _page_id, _url), do: :erlang.nif_error(:nif_not_loaded)
  def content(_runtime, _page_id), do: :erlang.nif_error(:nif_not_loaded)
  def title(_runtime, _page_id), do: :erlang.nif_error(:nif_not_loaded)
  def evaluate(_runtime, _page_id, _expression), do: :erlang.nif_error(:nif_not_loaded)
  def close_page(_runtime, _page_id), do: :erlang.nif_error(:nif_not_loaded)
end
