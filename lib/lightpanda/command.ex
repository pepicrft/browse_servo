defmodule Lightpanda.Command do
  @moduledoc false

  @common_flags [
    {:insecure_disable_tls_host_verification, "--insecure_disable_tls_host_verification"},
    {:obey_robots, "--obey_robots"},
    {:http_proxy, "--http_proxy", :string},
    {:proxy_bearer_token, "--proxy_bearer_token", :string},
    {:http_max_concurrent, "--http_max_concurrent", :string},
    {:http_max_host_open, "--http_max_host_open", :string},
    {:http_connect_timeout, "--http_connect_timeout", :string},
    {:http_timeout, "--http_timeout", :string},
    {:http_max_response_size, "--http_max_response_size", :string},
    {:log_level, "--log_level", :string},
    {:log_format, "--log_format", :string},
    {:log_filter_scopes, "--log_filter_scopes", :csv},
    {:user_agent_suffix, "--user_agent_suffix", :string},
    {:web_bot_auth_key_file, "--web_bot_auth_key_file", :string},
    {:web_bot_auth_keyid, "--web_bot_auth_keyid", :string},
    {:web_bot_auth_domain, "--web_bot_auth_domain", :string}
  ]

  @fetch_flags [
    {:dump, "--dump", :dump},
    {:strip_mode, "--strip_mode", :csv},
    {:with_base, "--with_base"},
    {:with_frames, "--with_frames"},
    {:wait_ms, "--wait_ms", :string},
    {:wait_until, "--wait_until", :string}
  ]

  @serve_flags [
    {:host, "--host", :string},
    {:port, "--port", :string},
    {:timeout, "--timeout", :string},
    {:cdp_max_connections, "--cdp_max_connections", :string},
    {:cdp_max_pending_connections, "--cdp_max_pending_connections", :string}
  ]

  @spec fetch(String.t(), keyword()) :: [String.t()]
  def fetch(url, opts) do
    ["fetch"] ++ build_flags(@common_flags, opts) ++ build_flags(@fetch_flags, opts) ++ [url]
  end

  @spec serve(keyword()) :: [String.t()]
  def serve(opts) do
    ["serve"] ++ build_flags(@common_flags, opts) ++ build_flags(@serve_flags, opts)
  end

  @spec mcp(keyword()) :: [String.t()]
  def mcp(opts) do
    ["mcp"] ++ build_flags(@common_flags, opts)
  end

  @spec version() :: [String.t()]
  def version, do: ["version"]

  defp build_flags(definitions, opts) do
    Enum.flat_map(definitions, fn
      {key, flag} ->
        case Keyword.get(opts, key) do
          true -> [flag]
          _ -> []
        end

      {key, flag, formatter} ->
        case Keyword.get(opts, key) do
          nil -> []
          false -> []
          true -> [flag]
          value -> [flag, format_value(formatter, value)]
        end
    end)
  end

  defp format_value(:csv, value), do: csv(value)
  defp format_value(:dump, value), do: dump_value(value)
  defp format_value(:string, value), do: to_string(value)

  defp csv(value) when is_list(value), do: Enum.join(value, ",")
  defp csv(value), do: to_string(value)

  defp dump_value(value) when is_atom(value), do: Atom.to_string(value)
  defp dump_value(value), do: to_string(value)
end
