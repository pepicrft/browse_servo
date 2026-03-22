defmodule Lightpanda.CDP.Client do
  @moduledoc false

  use WebSockex

  @type option :: {:owner, pid()}

  @spec start_link(String.t(), [option()]) :: GenServer.on_start()
  def start_link(url, opts \\ []) do
    state = %{
      next_id: 0,
      owner: Keyword.get(opts, :owner, self()),
      subscribers: MapSet.new(),
      waiters: %{}
    }

    WebSockex.start_link(url, __MODULE__, state, Keyword.take(opts, [:name]))
  end

  @spec command(pid(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def command(client, method, params \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, Application.get_env(:lightpanda, :cdp_timeout, 5_000))
    GenServer.call(client, {:command, method, params, Keyword.get(opts, :session_id)}, timeout)
  end

  @spec subscribe(pid(), pid()) :: :ok
  def subscribe(client, pid \\ self()) do
    GenServer.call(client, {:subscribe, pid})
  end

  @spec unsubscribe(pid(), pid()) :: :ok
  def unsubscribe(client, pid \\ self()) do
    GenServer.call(client, {:unsubscribe, pid})
  end

  @spec close(pid()) :: :ok
  def close(client) do
    WebSockex.cast(client, :close)
  end

  @impl true
  def handle_connect(_conn, state), do: {:ok, state}

  def handle_call({:subscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  def handle_call({:command, method, params, session_id}, from, state) do
    id = state.next_id + 1
    payload = encode_command(id, method, params, session_id)
    waiters = Map.put(state.waiters, id, from)
    {:reply, :ok, {:text, payload}, %{state | next_id: id, waiters: waiters}}
  end

  @impl true
  def handle_cast(:close, state) do
    {:close, state}
  end

  @impl true
  def handle_frame({:text, payload}, state) do
    case Jason.decode(payload) do
      {:ok, %{"id" => id, "result" => result}} ->
        {from, waiters} = Map.pop(state.waiters, id)
        if from, do: GenServer.reply(from, {:ok, result})
        {:ok, %{state | waiters: waiters}}

      {:ok, %{"id" => id, "error" => error}} ->
        {from, waiters} = Map.pop(state.waiters, id)
        if from, do: GenServer.reply(from, {:error, error})
        {:ok, %{state | waiters: waiters}}

      {:ok, %{"method" => method} = event} ->
        session_id = Map.get(event, "sessionId")
        params = Map.get(event, "params", %{})
        Enum.each(state.subscribers, &send(&1, {:lightpanda_cdp_event, method, params, session_id}))
        send(state.owner, {:lightpanda_cdp_event, method, params, session_id})
        {:ok, state}

      {:error, _reason} ->
        {:ok, state}
    end
  end

  def handle_frame(_frame, state), do: {:ok, state}

  defp encode_command(id, method, params, session_id) do
    %{
      "id" => id,
      "method" => method,
      "params" => params
    }
    |> maybe_put("sessionId", session_id)
    |> Jason.encode!()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
