defmodule Lightpanda.Runner do
  @moduledoc false

  @spec command(String.t(), [String.t()], keyword()) :: {String.t(), non_neg_integer()}
  def command(executable, args, opts \\ []) do
    env =
      opts
      |> Keyword.get(:env, [])
      |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)

    System.cmd(executable, args, stderr_to_stdout: true, env: env)
  end

  @spec open(String.t(), [String.t()], keyword()) :: port()
  def open(executable, args, opts \\ []) do
    env =
      opts
      |> Keyword.get(:env, [])
      |> Enum.map(fn {key, value} ->
        {to_charlist(to_string(key)), to_charlist(to_string(value))}
      end)

    Port.open(
      {:spawn_executable, executable},
      [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, args},
        {:env, env},
        {:line, 32_768}
      ]
    )
  end

  @spec close(port()) :: true
  def close(port) when is_port(port) do
    Port.close(port)
  end
end
