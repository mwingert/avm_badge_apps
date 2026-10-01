defmodule Badge.App.Thegoat.Menu do
  @moduledoc """
  The menu the page starts in, and that Esc leaves the game for.

  Pure, like `Badge.App.Thegoat.GameOver`: `handle_key/2` says what a key does and `items/4`
  is the display list to draw, so it is checked on the laptop. The page owns the screen.

  Up and Down (or W and S) move, Enter or Space picks, Esc goes back to the first screen;
  on the first screen the page lets Esc go home. Being in the menu means being out of the
  game: the page leaves the relay's room when Esc opens it, and Play starts a new life in
  a room.

  Two entries: the game, and where the badge stands with wifi and the relay.
  """

  # The default font is 8 pixels to a character, and 16 high.
  @char 8
  @high 16

  @back 0x101820
  @band 0x24507A
  @title 0xFFFF00
  @text 0xFFFFFF
  @dim 0x9AA8B8

  @doc "A menu on its first screen."
  def new, do: %{screen: :main, cursor: 0}

  @doc """
  What a key event does, as `Badge.Page.handle_key/2` gets it: `:play` when the game should be
  shown, `{:ok, menu}` with whatever changed, or `:ignore` for a key it has no use for, so the
  firmware still gets it (the shape keys go to other pages).
  """
  def handle_key(%{screen: :main, cursor: cursor} = menu, event) do
    cond do
      step?(event) -> {:ok, %{menu | cursor: 1 - cursor}}
      not pick?(event) -> :ignore
      cursor == 0 -> :play
      true -> {:ok, %{menu | screen: :status}}
    end
  end

  def handle_key(menu, event) do
    if pick?(event) or event == {:nav, :home} or event == {:move, :left},
      do: {:ok, %{menu | screen: :main}},
      else: :ignore
  end

  # Up or Down, W or S.
  defp step?({:move, dir}), do: dir == :up or dir == :down
  defp step?({:char, c}), do: c == ?w or c == ?W or c == ?s or c == ?S
  defp step?(_event), do: false

  # Enter or Space.
  defp pick?(event), do: event == {:edit, :newline} or event == {:char, ?\s}

  @doc """
  The display list. `info` is what the status screen says: `%{wifi: text, relay: text,
  badge: text}`, each short enough for a line.
  """
  def items(%{screen: :main, cursor: cursor}, _info, width, height) do
    [text(width, 24, @title, "GOAT GAME")] ++
      entry(width, 84, cursor == 0, "Play") ++
      entry(width, 116, cursor == 1, "Status") ++
      [text(width, height - 24, @dim, "Up Down  Enter"), back(width, height)]
  end

  def items(%{screen: :status}, info, width, height) do
    [
      text(width, 24, @title, "STATUS"),
      text(width, 84, @text, info.wifi),
      text(width, 108, @text, info.relay),
      text(width, 132, @text, info.badge),
      text(width, height - 24, @dim, "Esc  back"),
      back(width, height)
    ]
  end

  defp text(width, y, colour, text),
    do: {:text, div(width - byte_size(text) * @char, 2), y, :default16px, colour, :transparent, text}

  # The selected entry is marked and has a band behind it, under its text. The entries share
  # a left edge, so the marker is the only thing that moves.
  defp entry(width, y, selected, name) do
    x = div(width - 8 * @char, 2)
    marked = if selected, do: "> ", else: "  "
    colour = if selected, do: @text, else: @dim
    band = if selected, do: [{:rect, div(width, 2) - 100, y - 4, 200, @high + 8, @band}], else: []

    [{:text, x, y, :default16px, colour, :transparent, marked <> name}] ++ band
  end

  defp back(width, height), do: {:rect, 0, 0, width, height, @back}
end
