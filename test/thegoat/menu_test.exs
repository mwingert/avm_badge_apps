defmodule Badge.App.Thegoat.MenuTest do
  use ExUnit.Case, async: true

  alias Badge.App.Thegoat.Menu

  @width 320
  @height 240
  @info %{
    wifi: "Wifi: connected",
    relay: "Relay: online, 3 playing",
    badge: "Badge: A0F262EE6F6C"
  }

  defp items(menu, info \\ @info), do: Menu.items(menu, info, @width, @height)

  defp texts(menu, info \\ @info) do
    for {:text, _x, _y, _font, _fg, _bg, text} <- items(menu, info), do: text
  end

  defp press(menu, labels),
    do: Enum.reduce(labels, menu, fn label, m -> elem(Menu.handle_key(m, label), 1) end)

  describe "the first screen" do
    test "offers the game and the status" do
      assert texts(Menu.new()) |> Enum.take(3) == ["GOAT GAME", "> Play", "  Status"]
    end

    test "Up and Down (or W and S) move the cursor, and it wraps" do
      menu = Menu.new()
      assert press(menu, [{:move, :down}]).cursor == 1
      assert press(menu, [{:move, :down}, {:move, :down}]).cursor == 0
      assert press(menu, [{:move, :up}]).cursor == 1
      assert press(menu, [{:char, ?s}, {:char, ?w}, {:char, ?s}]).cursor == 1
    end

    test "Enter or Space on the game starts it" do
      assert Menu.handle_key(Menu.new(), {:edit, :newline}) == :play
      assert Menu.handle_key(Menu.new(), {:char, ?\s}) == :play
    end

    test "Enter or Space on the status opens that screen" do
      assert {:ok, %{screen: :status}} = Menu.handle_key(press(Menu.new(), [{:move, :down}]), {:edit, :newline})
      assert {:ok, %{screen: :status}} = Menu.handle_key(press(Menu.new(), [{:move, :down}]), {:char, ?\s})
    end

    test "Esc is not taken on the first screen, so the firmware takes the badge home" do
      assert Menu.handle_key(Menu.new(), {:nav, :home}) == :ignore
    end

    test "keys it has no use for are ignored, so the firmware still gets them" do
      menu = Menu.new()

      for label <- [{:char, ?q}, {:char, ?1}, {:edit, :backspace}, {:move, :left}],
          do: assert(Menu.handle_key(menu, label) == :ignore)
    end
  end

  describe "the other screens" do
    test "the status shows what it is told, on one line each" do
      lines = texts(%{Menu.new() | screen: :status})
      assert "STATUS" in lines
      for line <- Map.values(@info), do: assert(line in lines)
    end

    test "Esc, Enter, Space or Left go back to the first screen, keeping the cursor" do
      menu = press(Menu.new(), [{:move, :down}, {:edit, :newline}])
      assert menu.cursor == 1

      for label <- [{:nav, :home}, {:edit, :newline}, {:char, ?\s}, {:move, :left}] do
        assert {:ok, %{screen: :main, cursor: 1}} = Menu.handle_key(menu, label)
      end
    end

    test "Esc on a sub screen goes back even when a game is going, and does not resume it" do
      assert {:ok, %{screen: :main}} = Menu.handle_key(%{Menu.new() | screen: :status}, {:nav, :home})
    end
  end

  describe "the display list" do
    test "has the background last, so everything else is drawn over it" do
      for screen <- [:main, :status] do
        assert {:rect, 0, 0, @width, @height, _colour} =
                 List.last(items(%{Menu.new() | screen: screen}))
      end
    end

    test "the selected entry has a band behind it, under its text" do
      list = items(Menu.new())
      text = Enum.find_index(list, &match?({:text, _, _, _, _, _, "> Play"}, &1))
      band = Enum.find_index(list, &match?({:rect, _, _, 200, _, _}, &1))
      assert text < band
    end

    test "every item is on the screen" do
      for screen <- [:main, :status] do
        for item <- items(%{Menu.new() | screen: screen}) do
          case item do
            {:text, x, y, _font, _fg, _bg, text} ->
              assert x >= 0 and x + byte_size(text) * 8 <= @width
              assert y >= 0 and y + 16 <= @height

            {:rect, x, y, w, h, _colour} ->
              assert x >= 0 and y >= 0 and x + w <= @width and y + h <= @height
          end
        end
      end
    end
  end
end
