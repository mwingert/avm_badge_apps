defmodule Badge.App.Thegoat.GameOver do
  @moduledoc """
  The screen for a player the goat has caught: the goat itself, close and
  hunting, on dark red, with how long they lasted and what to do next.

  A display list like any frame, drawn once and left up until a key is pressed.
  The goat is `Engine.sprites/5` looking at one a cell and three quarters away,
  so it is the same goat as in the game.
  """

  alias Badge.App.Thegoat.Engine

  # The default font is 8 pixels to a character.
  @char 8
  @back 0x3A0808
  @band 0xB01010

  # Where the goat is looked at from: open floor on row 9, facing east.
  @eye_x 2 * 256 + 128
  @eye_y 9 * 256 + 128
  @goat_at 448

  def items(grid, survived_s, width, height) do
    goat =
      Engine.sprites(
        grid,
        %{x: @eye_x, y: @eye_y, a: 0},
        [{:goat, @eye_x + @goat_at, @eye_y, true}],
        width,
        height
      )

    [
      text(width, 22, 0xFFFFFF, "GAME OVER"),
      text(width, 50, 0xFFD0D0, "The evil goat got you"),
      text(width, height - 44, 0xFFD0D0, "You lasted #{survived_s} s"),
      text(width, height - 24, 0xFFFF00, "Press any key")
    ] ++
      goat ++
      [{:rect, 0, 16, width, 28, @band}, {:rect, 0, 0, width, height, @back}]
  end

  defp text(width, y, colour, text) do
    x = div(width - byte_size(text) * @char, 2)
    {:text, x, y, :default16px, colour, :transparent, text}
  end
end
