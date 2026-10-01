defmodule Badge.App.Thegoat.Link do
  @moduledoc """
  The Goat game page's websocket to the relay server, open only while the page is.

  The connection is `Badge.Chat.Socket`'s, the ESP-IDF component that does the TCP, the
  TLS and the framing on a task of its own and reconnects by itself, so `:connected`
  arrives on every reconnection and the room is joined each time. `open/0` and
  `close/0` are casts and safe to repeat: the page calls `open/0` from every tick.

  It sends `Badge.UI`, which hands them to the page on screen:

    * `{:thegoat, :ready}` when the connection is up but this badge is not in a room,
      `{:thegoat, :up}` once the server has put it in one, and `{:thegoat, :down}` when
      the connection is lost
    * `{:thegoat, {:players, [{x, y, colour}], goat}}` once a second: everyone else,
      and the goat, `{x, y, hunting}` or nil
    * `{:thegoat, :caught}` when the goat has caught this badge; `respawn/0` says it
      is back

  The room is only joined while it is wanted: from `join/0` until `leave/0`, which goes out
  of the room at once and frees its slot while the connection stays open. The menu is out
  of the room, so nobody sees this badge and the goat cannot catch it.

  The relay is the `thegoat_url` NVS key, or a default, and the token it asks for
  the `thegoat_token` key.
  """

  use GenServer

  alias Badge.Chat.Socket
  alias Badge.Identity
  alias Badge.Nvs
  alias Badge.App.Thegoat.Room
  alias Badge.Wifi

  @default_url "wss://evilgoat-relay.fly.dev"

  # The token the relay asks for, when there is no `thegoat_token` key. It is public, in
  # this repo and in the pack, like the secret the firmware's update link has built in: it
  # keeps casual visitors out, not anyone who reads it. If it is abused the relay's token
  # is changed and a new version of this app carries the new one.
  @default_token "7411d88d1c0034a4"

  @tick 2_000
  # A heartbeat about every 24 seconds; Phoenix drops a connection that goes quiet.
  @beats 12

  def start_link(_arg), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Starts the link unless it is running. A store app has no place in the firmware's supervisor,
  so the page starts it, unlinked: a crash here must not take the UI down with it.
  """
  def ensure_started do
    case :erlang.whereis(__MODULE__) do
      :undefined -> GenServer.start(__MODULE__, :ok, name: __MODULE__)
      _pid -> {:ok, :erlang.whereis(__MODULE__)}
    end
  end

  @spec open() :: :ok
  def open, do: GenServer.cast(__MODULE__, :open)

  @spec close() :: :ok
  def close, do: GenServer.cast(__MODULE__, :close)

  @doc "Joins a room, now if the connection is up and otherwise as soon as it is."
  @spec join() :: :ok
  def join, do: GenServer.cast(__MODULE__, :join)

  @doc "Goes out of the room, and stays out until `join/0`."
  @spec leave() :: :ok
  def leave, do: GenServer.cast(__MODULE__, :leave)

  @doc "Tells the server where this badge stands. Dropped while not in a room."
  @spec publish(integer, integer) :: :ok
  def publish(x, y), do: GenServer.cast(__MODULE__, {:publish, x, y})

  @doc "Back in the game after being caught. Dropped while not in a room."
  @spec respawn() :: :ok
  def respawn, do: GenServer.cast(__MODULE__, :respawn)

  @impl true
  def init(:ok) do
    start_ticker()

    {:ok, %{want: false, room: false, connected: false, port: nil, slot: nil, joins: 0, ref: 0, beat: 0}}
  end

  @impl true
  def handle_call(_message, _from, state), do: {:reply, :error, state}

  @impl true
  def handle_cast(:open, %{want: true} = state), do: {:noreply, state}
  def handle_cast(:open, state), do: {:noreply, connect(%{state | want: true})}
  def handle_cast(:close, state), do: {:noreply, shut(%{state | want: false, room: false})}

  def handle_cast(:join, %{slot: nil, connected: true} = state) do
    state = %{state | room: true, joins: state.joins + 1}
    send_frame(state.port, Room.join(join_ref(state)))

    {:noreply, state}
  end

  def handle_cast(:join, state), do: {:noreply, %{state | room: true}}

  def handle_cast(:leave, %{slot: slot} = state) when slot != nil do
    state = %{state | room: false, ref: state.ref + 1, slot: nil}
    send_frame(state.port, Room.leave(join_ref(state), Integer.to_string(state.ref)))
    send(Badge.UI, {:thegoat, :ready})

    {:noreply, state}
  end

  def handle_cast(:leave, state), do: {:noreply, %{state | room: false}}

  def handle_cast({:publish, x, y}, %{slot: slot, port: port} = state) when slot != nil do
    state = %{state | ref: state.ref + 1}
    send_frame(port, Room.pos(join_ref(state), Integer.to_string(state.ref), x, y))

    {:noreply, state}
  end

  def handle_cast({:publish, _x, _y}, state), do: {:noreply, state}

  def handle_cast(:respawn, %{slot: slot, port: port} = state) when slot != nil do
    state = %{state | ref: state.ref + 1}
    send_frame(port, Room.respawn(join_ref(state), Integer.to_string(state.ref)))

    {:noreply, state}
  end

  def handle_cast(:respawn, state), do: {:noreply, state}

  @impl true
  def handle_info(:tick, state), do: {:noreply, state |> connect() |> beat()}

  # The port in these messages is not matched, and is not the one to send on: the
  # driver's port term is not the one open/4 returned, so a pinned match drops every
  # message without a word.
  def handle_info({:websocket, _port, :connected}, %{want: true} = state) do
    state = %{state | joins: state.joins + 1, slot: nil, connected: true}

    if state.room do
      send_frame(state.port, Room.join(join_ref(state)))
    else
      send(Badge.UI, {:thegoat, :ready})
    end

    {:noreply, state}
  end

  def handle_info({:websocket, _port, {:text, frame}}, state) do
    {:noreply, heard(Room.interpret(frame, state.slot), state)}
  end

  def handle_info({:websocket, _port, {:closed, _reason}}, state), do: {:noreply, down(state)}
  def handle_info({:websocket, _port, {:error, _reason}}, state), do: {:noreply, down(state)}
  def handle_info(_message, state), do: {:noreply, state}

  # A join that was answered after leaving was asked for: out again, and not said to the page.
  defp heard({:joined, _slot}, %{room: false} = state) do
    state = %{state | ref: state.ref + 1}
    send_frame(state.port, Room.leave(join_ref(state), Integer.to_string(state.ref)))
    state
  end

  defp heard({:joined, slot}, state) do
    :io.format(~c"Goat game: joined the relay, slot ~p~n", [slot])
    send(Badge.UI, {:thegoat, :up})
    %{state | slot: slot}
  end

  defp heard({:players, players, goat}, state) do
    send(Badge.UI, {:thegoat, {:players, players, goat}})
    state
  end

  defp heard(:caught, state) do
    send(Badge.UI, {:thegoat, :caught})
    state
  end

  defp heard(:ignore, state), do: state

  # A certificate is not yet valid at the epoch, so this waits for the clock as well as
  # for an address, as the chat does.
  defp connect(%{want: true, port: nil} = state) do
    case wifi_status() do
      %{radio: :connected, synced: true} -> opening(state)
      _not_ready -> state
    end
  end

  defp connect(state), do: state

  # A wifi process that is not there, or is being restarted, is a wifi that is not ready.
  defp wifi_status do
    Wifi.status()
  catch
    _kind, _reason -> nil
  end

  defp opening(state) do
    chip = Identity.format(Identity.chip_id())
    base = Socket.base_url(Nvs.get(:thegoat_url) || @default_url)

    case :websocket_client.open(with_token(Socket.opts(base, chip, "raycaster"), Nvs.get(:thegoat_token) || @default_token)) do
      {:ok, port} -> %{state | port: port}
      {:error, _reason} -> state
    end
  end

  # `Socket.opts/3` builds the whole connection; the token rides on its URL, as the relay wants.
  defp with_token(opts, nil), do: opts
  defp with_token(opts, value), do: %{opts | url: opts.url <> "&token=" <> value}

  defp down(state) do
    if state.slot != nil or state.connected, do: send(Badge.UI, {:thegoat, :down})
    %{state | slot: nil, connected: false}
  end

  defp shut(%{port: nil} = state), do: state

  defp shut(state) do
    Socket.close(state.port)
    down(%{state | port: nil})
  end

  defp beat(%{beat: beat, slot: slot} = state) when beat >= @beats and slot != nil do
    send_frame(state.port, Room.heartbeat())
    %{state | beat: 0}
  end

  defp beat(%{beat: beat} = state), do: %{state | beat: beat + 1}

  defp join_ref(state), do: Integer.to_string(state.joins)

  defp send_frame(port, frame) do
    case Socket.send_frame(port, frame) do
      :ok -> :ok
      {:error, reason} -> :io.format(~c"Goat game: refused ~p~n", [reason])
    end
  end

  defp start_ticker do
    link = self()
    spawn_link(fn -> tick_loop(link) end)
  end

  defp tick_loop(link) do
    Process.sleep(@tick)
    send(link, :tick)
    tick_loop(link)
  end
end
