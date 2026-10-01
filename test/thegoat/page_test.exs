defmodule Badge.App.Thegoat.PageTest do
  use ExUnit.Case, async: true

  alias Badge.App.Thegoat.Page
  alias Badge.Theme

  # The page starts in the menu; most of what is tested here is the game.
  defp game, do: %{Page.init() | mode: :game}

  describe "identity" do
    test "names itself for the home grid" do
      assert Page.title() == "Goat game"
      assert Page.icon() in Badge.Icons.names()
    end

    test "asks for the shortest gap the ticker offers" do
      assert Page.refresh(Page.init()) == 100
    end

    test "starts standing still" do
      assert %{at: nil, mode: :menu} = Page.init()
    end
  end

  describe "the keys the engine reads" do
    # The firmware's labels are charlists, and the engine has to know them.
    test "every direction moves or turns the player" do
      grid = Badge.App.Thegoat.Engine.grid()
      start = %{x: 11 * 256 + 128, y: 9 * 256 + 128, a: 0}

      for label <- [
            ~c"Up",
            ~c"W",
            ~c"Down",
            ~c"S",
            ~c"Q",
            ~c"E",
            ~c"Left",
            ~c"A",
            ~c"Right",
            ~c"D"
          ] do
        refute Badge.App.Thegoat.Engine.step(grid, start, [label], 200) == start
      end
    end

    test "keys with no meaning here change nothing" do
      grid = Badge.App.Thegoat.Engine.grid()
      start = %{x: 11 * 256 + 128, y: 9 * 256 + 128, a: 0}

      assert Badge.App.Thegoat.Engine.step(grid, start, [~c"Space", ~c"Ctrl", ~c"1"], 200) == start
    end
  end

  describe "render/1" do
    test "stays inside the content area, below the title bar" do
      items = Page.render(game())

      assert items != []

      for {:rect, x, y, w, h, _colour} <- items do
        assert x >= 0 and x + w <= Theme.width()
        assert y >= Theme.content_top() and y + h <= Theme.height()
      end
    end

    test "draws no background, which is the router's job" do
      items = Page.render(game())
      rects = for {:rect, 0, y, w, h, _} <- items, w == Theme.width(), do: {y, h}

      # Only the floor and ceiling span the panel, and together they fill the view only.
      assert length(rects) == 2

      assert rects |> Enum.map(fn {_y, h} -> h end) |> Enum.sum() ==
               Theme.height() - Theme.content_top()
    end
  end

  describe "other players" do
    @figure {900, 300, 0xE0433A}

    defp with_others(others),
      do: elem(Page.handle_info({:thegoat, {:players, others, nil}}, game()), 1)

    test "offline until the relay puts the badge in a room" do
      assert Enum.any?(
               Page.render(game()),
               &match?({:text, _, _, _, _, _, "offline"}, &1)
             )
    end

    test "the line says how many are playing, counting this badge" do
      up = elem(Page.handle_info({:thegoat, :up}, game()), 1)

      assert Enum.any?(
               Page.render(up),
               &match?({:text, _, _, _, _, _, "online, 1 playing"}, &1)
             )

      two = %{up | others: [@figure]}

      assert Enum.any?(
               Page.render(two),
               &match?({:text, _, _, _, _, _, "online, 2 playing"}, &1)
             )
    end

    test "the snapshot replaces who is around, and losing the link empties it" do
      state = with_others([@figure])

      assert %{others: [@figure]} = state
      assert {:ok, %{others: []}} = Page.handle_info({:thegoat, {:players, [], nil}}, state)
      assert {:ok, %{others: [], link: :off}} = Page.handle_info({:thegoat, :down}, state)
    end

    test "the link coming up makes the page say where it is at once" do
      state = %{game() | sent: 12_345}

      assert {:ok, %{link: :up, sent: nil}} = Page.handle_info({:thegoat, :up}, state)
    end

    test "a figure in view is drawn in front of the walls" do
      # The spawn point faces east along row 1, so someone four cells ahead is in view.
      ahead = {384 + 4 * 256, 384, 0xE0433A}
      without = Page.render(game())
      with_figure = Page.render(with_others([ahead]))

      # The status line, then a head and a body, then exactly what was there before.
      assert length(with_figure) == length(without) + 2
      assert Enum.drop(with_figure, 3) == Enum.drop(without, 1)
    end

    test "the goat is drawn when the relay says where it is, and is gone when it is not" do
      # Four cells ahead of the spawn point, facing east along row 1.
      state = game()
      without = Page.render(state)

      {:ok, seen} =
        Page.handle_info({:thegoat, {:players, [], {384 + 4 * 256, 384, true}}}, state)

      assert %{goat: {_x, _y, true}} = seen
      # Five rectangles at this distance, thirteen close up.
      assert length(Page.render(seen)) >= length(without) + 5

      {:ok, gone} = Page.handle_info({:thegoat, {:players, [], nil}}, seen)
      assert Page.render(gone) == without
    end

    test "the line says how long this life has lasted once there is a goat" do
      up = elem(Page.handle_info({:thegoat, :up}, game()), 1)
      {:ok, up} = Page.handle_info({:thegoat, {:players, [], {900, 900, false}}}, up)

      assert Enum.any?(
               Page.render(up),
               &match?({:text, _, _, _, _, _, "online, 1 playing, alive 0 s"}, &1)
             )
    end

    test "being caught shows the game over screen, inside the content area" do
      {:ok, caught} = Page.handle_info({:thegoat, :caught}, game())
      items = Page.render(caught)

      assert Enum.any?(items, &match?({:text, _, _, _, _, _, "GAME OVER"}, &1))

      for {:text, _x, y, _font, _fg, _bg, _text} <- items, do: assert(y >= Theme.content_top())
      for {:rect, _x, y, _w, _h, _c} <- items, do: assert(y >= Theme.content_top())
    end

    test "a catch is taken once, and the game over screen outlasts a key still held" do
      {:ok, caught} = Page.handle_info({:thegoat, :caught}, game())

      assert Page.handle_info({:thegoat, :caught}, caught) == :ignore
      # Without a key held, and within the time it stays up, ticking changes nothing.
      assert Page.tick(caught).caught == caught.caught
    end

    test "a message it does not know is ignored" do
      assert Page.handle_info(:nonsense, game()) == :ignore
      assert Page.handle_info({:thegoat, :sideways}, game()) == :ignore
    end
  end

  describe "the menu" do
    alias Badge.App.Thegoat.Menu

    defp texts(state) do
      for {:text, _x, _y, _font, _fg, _bg, text} <- Page.render(state), do: text
    end

    test "the page starts in the menu, out of the game" do
      state = Page.init()

      assert %{mode: :menu} = state
      assert "GOAT GAME" in texts(state)
      assert "> Play" in texts(state)
    end

    test "the menu stays inside the content area and does not move the player" do
      state = Page.init()

      for {:rect, x, y, w, h, _colour} <- Page.render(state) do
        assert x >= 0 and x + w <= Theme.width()
        assert y >= Theme.content_top() and y + h <= Theme.height()
      end

      assert Page.tick(%{state | held: [~c"W"]}) == %{state | held: [~c"W"]}
    end

    test "Enter on Play starts a new life in the game" do
      {:ok, state} = Page.handle_key({:edit, :newline}, %{Page.init() | sent: 5, at: 9})

      assert %{mode: :game, sent: nil, at: nil, caught: nil} = state
      assert state.player == Badge.App.Thegoat.Engine.new()
    end

    test "Down and W S move, Enter on Status opens it, Esc goes back" do
      {:ok, state} = Page.handle_key({:move, :down}, Page.init())
      assert "> Status" in texts(state)

      {:ok, state} = Page.handle_key({:edit, :newline}, state)
      assert "STATUS" in texts(state)
      assert Enum.any?(texts(state), &String.starts_with?(&1, "Relay: offline"))

      # Esc on a screen that is not the first goes back to it, and is taken.
      assert {:ok, %{menu: %{screen: :main}}} = Page.handle_key({:nav, :home}, state)

      {:ok, state} = Page.handle_key({:char, ?s}, Page.init())
      {:ok, state} = Page.handle_key({:char, ?w}, state)
      assert "> Play" in texts(state)
      {:ok, state} = Page.handle_key({:char, ?S}, state)
      {:ok, state} = Page.handle_key({:char, ?\s}, state)
      assert "STATUS" in texts(state)
    end

    test "Esc on the menu's first screen is not taken, so it goes home" do
      assert Page.handle_key({:nav, :home}, Page.init()) == :ignore
    end

    test "Esc in the game goes back to the menu, without the others and the goat" do
      state = %{game() | others: [{900, 300, 0xE0433A}], goat: {900, 900, true}, link: :up}

      assert {:ok, back} = Page.handle_key({:nav, :home}, state)
      assert %{mode: :menu, others: [], goat: nil, link: :ready, at: nil} = back
      assert "GOAT GAME" in texts(back)
    end

    test "keys with no meaning in the menu are left for the firmware" do
      assert Page.handle_key({:char, ?x}, Page.init()) == :ignore
    end

    test "the game does not take keys: they are read as held" do
      for event <- [{:move, :up}, {:char, ?w}] do
        assert Page.handle_key(event, game()) == :ignore
      end
    end

    test "the relay saying ready puts the link at ready, and up shows in the status" do
      {:ok, ready} = Page.handle_info({:thegoat, :ready}, %{Page.init() | link: :off})
      assert %{link: :ready} = ready
      assert {:ok, %{link: :up}} = Page.handle_info({:thegoat, :up}, ready)
    end
  end

  describe "held keys" do
    # Keys arrive as `{:held, labels}` from `Badge.Keyboard.watch/1`, whenever the set changes,
    # and the page keeps the latest set to move by on each tick.
    test "starts with nothing held" do
      assert %{held: []} = game()
    end

    test "the keyboard's set replaces what was held, and an empty set clears it" do
      assert {:ok, %{held: [~c"Left", ~c"W"]}} =
               Page.handle_info({:held, [~c"Left", ~c"W"]}, game())

      {:ok, state} = Page.handle_info({:held, [~c"W"]}, game())
      assert {:ok, %{held: []}} = Page.handle_info({:held, []}, state)
    end
  end
end
