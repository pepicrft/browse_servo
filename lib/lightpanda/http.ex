defmodule Lightpanda.HTTP do
  @moduledoc false

  @spec get_json!(String.t(), keyword()) :: map()
  def get_json!(url, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    Req.get!(url, headers: headers).body
  end

  @spec download!(String.t(), String.t(), keyword()) :: :ok
  def download!(url, path, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    body = Req.get!(url, headers: headers, compressed: false).body
    File.write!(path, body)
    :ok
  end
end
