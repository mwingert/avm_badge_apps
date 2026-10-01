defmodule Badge.App.Thegoat.Page do
  @moduledoc """
  A Wolfenstein-style 3D view of a small map, drawn by `Badge.App.Thegoat.Engine`, with the other
  badges walking around in it.

  It starts in `Badge.App.Thegoat.Menu` (Play, Controls, Status). Esc in the game goes back
  to it, and Esc on the menu's first screen leaves. Being in the menu means being out of the
  game: the page leaves the relay's room, so nobody sees this badge and the goat cannot
  catch it, and Play joins a room again and starts a new life with the count from zero. The
  badge does not join a room until the first Play.

  Arrows or W A S D move and turn, Q and E strafe. The keys are read as held
  rather than tapped, from `Badge.Keyboard.watch/1`, which says whenever the set changes: key events only arrive
  on press and auto-repeat, which is no way to walk.

  Every badge that has this page open tells a relay server where it stands twice a second,
  see `Badge.App.Thegoat.Link`, and is told where the others are: they are drawn as coloured
  figures. The line at the bottom says whether the link is up, how many are playing and how
  long this life has lasted. Without wifi it is a room to walk around in on your own.

  The relay also has an evil goat in every room, which hunts the players. When it catches
  this badge the page shows `Badge.App.Thegoat.GameOver` until a key is pressed, tells the relay
  the badge is back and starts again where the goat is farthest. The four LEDs are left
  alone: the goat's warning glow needs a pattern the LED driver has no place for.

  The map is fetched with `Badge.App.Thegoat.Engine.grid/0` once per call and never kept in the
  state: AtomVM copies a module literal onto the heap each time it is looked up, so the
  lookup must not be in a per-ray loop, and a term that size does not belong in the state
  `Badge.UI` holds either.
  """

  use Badge.Page

  alias Badge.Identity
  alias Badge.Keyboard
  alias Badge.App.Thegoat.Link
  alias Badge.Theme
  alias Badge.Wifi
  alias Badge.App.Thegoat.Engine
  alias Badge.App.Thegoat.GameOver
  alias Badge.App.Thegoat.Menu

  # The view fills what is under the title bar.
  @view_w Theme.width()
  @view_h Theme.height() - Theme.content_top()

  # The most one step may move, so a long stall does not fling the player through a wall
  # in a single go. The engine's own clamp is per axis.
  @max_dt 250

  # How often to say where we are. The relay hands out one snapshot a second and forgets
  # a badge that is quiet for five seconds, but its goat judges a catch on the last
  # position it heard, so twice a second keeps that fairer.
  @announce_ms 500

  # How long the game over screen stays whatever is pressed, so a key held while running
  # from the goat does not skip it.
  @over_ms 1_500

  @impl true
  def title, do: "Goat game"

  @impl true
  def icon, do: :clover

  @impl true
  def refresh(_state), do: 100

  # `mode` is `:menu` or `:game`, and `menu` is where the menu is. `at` is when the player last moved, or nil while standing still. `others` is what the
  # relay last said, ready for the engine, and `goat` is where it says the goat is, or
  # nil. `sent` is when we last said where we are, `born` when this life began, and
  # `caught` is nil, or `{when, seconds lasted}` while the game over screen is up.
  @impl true
  def init do
    Link.ensure_started()
    Keyboard.watch(self())

    %{
      mode: :menu,
      menu: Menu.new(),
      held: [],
      player: Engine.new(),
      at: nil,
      others: [],
      goat: nil,
      link: :off,
      sent: nil,
      born: now(),
      caught: nil
    }
  end

  @impl true
  def tick(state) do
    Link.open()
    now = now()

    case state do
      %{mode: :menu} -> state
      %{caught: nil} -> state |> walk(now) |> tell(now)
      %{caught: caught} -> revive(state, caught, now)
    end
  end

  # Esc in the game goes back to the menu, out of the room. Esc on the menu's first screen
  # is not taken, so it goes home; on the others it goes back to the first.
  @impl true
  def handle_key({:nav, :home}, %{mode: :game} = state) do
    Link.leave()

    {:ok, %{state | mode: :menu, menu: Menu.new(), link: ready(state.link), others: [], goat: nil, at: nil}}
  end

  def handle_key({:nav, :home}, %{mode: :menu, menu: %{screen: :main}}), do: :ignore

  def handle_key(event, %{mode: :menu, menu: menu} = state) do
    case Menu.handle_key(menu, event) do
      :play -> {:ok, play(state)}
      {:ok, menu} -> {:ok, %{state | menu: menu}}
      :ignore -> :ignore
    end
  end

  def handle_key(_event, _state), do: :ignore

  # Into the game, as a new life: the start, a room joined, and the count from nothing.
  defp play(state) do
    Link.join()

    %{state | mode: :game, player: Engine.new(), at: nil, sent: nil, born: now(), caught: nil}
  end

  defp ready(:up), do: :ready
  defp ready(link), do: link

  @impl true
  def handle_info({:held, labels}, state), do: {:ok, %{state | held: labels}}

  def handle_info({:thegoat, :up}, state), do: {:ok, %{state | link: :up, sent: nil}}

  def handle_info({:thegoat, :ready}, state),
    do: {:ok, %{state | link: :ready, others: [], goat: nil}}

  def handle_info({:thegoat, :down}, state),
    do: {:ok, %{state | link: :off, others: [], goat: nil}}

  def handle_info({:thegoat, {:players, others, goat}}, state),
    do: {:ok, %{state | others: others, goat: goat}}

  def handle_info({:thegoat, :caught}, %{caught: nil, born: born} = state) do
    now = now()
    {:ok, %{state | caught: {now, div(now - born, 1000)}}}
  end

  def handle_info(_message, _state), do: :ignore

  @impl true
  def leave(_state) do
    Keyboard.unwatch()
    Link.close()
  end

  @impl true
  def render(%{mode: :menu, menu: menu, link: link, others: others}) do
    info = %{wifi: wifi_line(), relay: relay_line(link, length(others)), badge: badge_line()}

    shift(Menu.items(menu, info, @view_w, @view_h), Theme.content_top(), [])
  end

  def render(%{caught: {_when, lasted}}) do
    scene = GameOver.items(Engine.grid(), lasted, @view_w, @view_h)

    shift(scene, Theme.content_top(), [])
  end

  def render(%{player: player, others: others, goat: goat, link: link, born: born}) do
    grid = Engine.grid()
    figures = Engine.sprites(grid, player, goat(goat, others), @view_w, @view_h)
    walls = Engine.frame(grid, player, @view_w, @view_h)
    scene = shift(:lists.append(figures, walls), Theme.content_top(), [])

    [status(link, length(others), goat, born) | scene]
  end

  defp goat(nil, others), do: others
  defp goat({x, y, hunting}, others), do: [{:goat, x, y, hunting} | others]

  defp walk(%{player: player, at: at} = state, now) do
    case state.held do
      [] ->
        %{state | at: nil}

      held ->
        dt = if at == nil, do: 100, else: min(now - at, @max_dt)

        %{state | player: Engine.step(Engine.grid(), player, held, dt), at: now}
    end
  end

  defp tell(%{link: :up, sent: sent, player: player} = state, now) do
    if sent == nil or now - sent >= @announce_ms do
      Link.publish(player.x, player.y)
      %{state | sent: now}
    else
      state
    end
  end

  defp tell(state, _now), do: state

  # After the game over screen a key press brings the badge back, once the screen has
  # been up for a while. The relay is told, and the badge starts again where the goat is
  # not.
  defp revive(%{goat: goat} = state, {since, _lasted}, now) do
    if now - since >= @over_ms and state.held != [] do
      Link.respawn()

      %{state | player: Engine.respawn(goat), at: nil, sent: nil, born: now, caught: nil}
    else
      state
    end
  end

  defp status(:off, _others, _goat, _born), do: line("offline")
  defp status(:ready, _others, _goat, _born), do: line("connecting")

  defp status(:up, others, nil, _born),
    do: line("online, " <> :erlang.integer_to_binary(others + 1) <> " playing")

  defp status(:up, others, _goat, born) do
    line(
      "online, " <>
        :erlang.integer_to_binary(others + 1) <>
        " playing, alive " <> :erlang.integer_to_binary(div(now() - born, 1000)) <> " s"
    )
  end

  # What the status screen says, a line each.
  defp wifi_line do
    if Wifi.status().radio == :connected, do: "Wifi: connected", else: "Wifi: not connected"
  catch
    _kind, _reason -> "Wifi: not connected"
  end

  defp relay_line(:up, others), do: "Relay: online, " <> :erlang.integer_to_binary(others + 1) <> " playing"
  defp relay_line(:ready, _others), do: "Relay: ready"
  defp relay_line(:off, _others), do: "Relay: offline"

  defp badge_line do
    "Badge: " <> Identity.format(Identity.chip_id())
  catch
    _kind, _reason -> "Badge: unknown"
  end

  defp line(text), do: {:text, 4, Theme.height() - 18, :default16px, Theme.fg(), Theme.bg(), text}

  # The engine draws from y = 0; the title bar takes the top of the panel.
  defp shift([], _top, acc), do: :lists.reverse(acc)

  defp shift([{:rect, x, y, w, h, colour} | rest], top, acc) do
    shift(rest, top, [{:rect, x, y + top, w, h, colour} | acc])
  end

  defp shift([{:text, x, y, font, fg, bg, text} | rest], top, acc) do
    shift(rest, top, [{:text, x, y + top, font, fg, bg, text} | acc])
  end

  defp now, do: :erlang.monotonic_time(:millisecond)
end
