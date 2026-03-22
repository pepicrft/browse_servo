defmodule Lightpanda.CLI do
  @moduledoc false

  alias Lightpanda.Binary
  alias Lightpanda.Command
  alias Lightpanda.FetchResult

  @spec fetch(String.t(), keyword()) :: {:ok, FetchResult.t()} | {:error, term()}
  def fetch(url, opts \\ []) do
    with {:ok, binary_path} <- Binary.ensure_installed(opts) do
      args = Command.fetch(url, opts)
      {output, exit_status} = runner_module().command(binary_path, args, opts)

      case exit_status do
        0 ->
          {:ok,
           %FetchResult{
             binary_path: binary_path,
             command: [binary_path | args],
             exit_status: exit_status,
             output: output,
             url: url
           }}

        _ ->
          {:error, {:lightpanda_failed, exit_status, output}}
      end
    end
  rescue
    error -> {:error, error}
  end

  @spec version(keyword()) :: {:ok, String.t()} | {:error, term()}
  def version(opts \\ []) do
    with {:ok, binary_path} <- Binary.ensure_installed(opts) do
      case runner_module().command(binary_path, Command.version(), opts) do
        {output, 0} -> {:ok, String.trim(output)}
        {output, status} -> {:error, {:lightpanda_failed, status, output}}
      end
    end
  rescue
    error -> {:error, error}
  end

  defp runner_module do
    Application.get_env(:lightpanda, :runner, Lightpanda.Runner)
  end
end
