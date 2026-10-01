defmodule Badge.App.Magic8.Page do
  @moduledoc """
  A Magic 8-Ball. Ask it a yes-or-no question and shake the badge: the 8
  wobbles while it shakes, and once the ball settles the answer rises out
  of the ink on a blue triangle, fading in from the background. The LEDs
  flash green, amber or red with its mood.

  Enter or space shakes it too, for a badge lying on a desk.
  """

  use Badge.Page

  alias Badge.App.Magic8.Ball
  alias Badge.App.Magic8.Shapes
  alias Badge.Color
  alias Badge.FontType
  alias Badge.Pixels
  alias Badge.Readout
  alias Badge.Sensors
  alias Badge.Theme

  # The previous reading stays out of the page state, so sensor noise never repaints.
  @last {__MODULE__, :last}

  @wobble 8
  @float Shapes.headroom()
  @line_h 16
  @answer_fg 0xFFFFFF

  @hint "shake, or press Enter"
  @hint_y 212

  @impl true
  def title, do: "Magic 8-Ball"

  @impl true
  def icon, do: :circle

  @impl true
  def init, do: Ball.new()

  @impl true
  def handle_key({:edit, :newline}, ball), do: {:ok, Ball.shake(ball)}
  def handle_key({:char, ?\s}, ball), do: {:ok, Ball.shake(ball)}
  def handle_key(_event, _ball), do: :ignore

  @impl true
  def tick(ball) do
    accel = Sensors.acceleration()

    case Ball.step(ball, Ball.jerk(:erlang.put(@last, accel), accel)) do
      %{phase: :settled} = settled -> reveal(settled)
      next -> next
    end
  end

  defp reveal(ball) do
    <<roll::16>> = :crypto.strong_rand_bytes(2)
    answered = Ball.reveal(ball, roll)
    Pixels.flash(Ball.hue(answered))
    answered
  end

  @impl true
  def leave(_ball) do
    :erlang.erase(@last)
    :ok
  end

  @impl true
  def render(%{phase: :answer} = ball) do
    risen = Ball.risen(ball)
    face = blend(Theme.bg(), Shapes.blue(), risen)
    ink = blend(face, @answer_fg, risen)
    dy = div(@float * (100 - risen) * (100 - risen), 10_000)

    answer(Ball.lines(ball), dy, ink, face) ++ Shapes.triangle(face, dy)
  end

  def render(%{wobble: 0}), do: [hint() | Shapes.front()]
  def render(%{wobble: wobble}), do: [hint() | shift(Shapes.front(), wobble * @wobble)]

  defp answer(lines, dy, fg, bg) do
    top = Shapes.centre_y() + dy - div(length(lines) * @line_h, 2)
    place(lines, top, fg, bg, [])
  end

  defp place([], _y, _fg, _bg, acc), do: :lists.reverse(acc)

  defp place([line | rest], y, fg, bg, acc) do
    item = {:text, Readout.centre_x(line), y, FontType.body(), fg, bg, line}
    place(rest, y + @line_h, fg, bg, [item | acc])
  end

  # `percent` of the way from one 0xRRGGBB colour to another.
  defp blend(from, to, percent) do
    Color.rgb888(
      {mix(div(from, 0x10000), div(to, 0x10000), percent), mix(rem(div(from, 0x100), 0x100), rem(div(to, 0x100), 0x100), percent),
       mix(rem(from, 0x100), rem(to, 0x100), percent)}
    )
  end

  defp mix(a, b, percent), do: a + div((b - a) * percent, 100)

  defp shift(rects, dx),
    do: :lists.map(fn {:rect, x, y, w, h, c} -> {:rect, x + dx, y, w, h, c} end, rects)

  defp hint do
    {:text, Readout.centre_x(@hint), @hint_y, FontType.body(), Theme.dim(), Theme.bg(), @hint}
  end
end
