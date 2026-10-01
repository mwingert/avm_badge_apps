defmodule Badge.App.Magic8.Ball do
  @moduledoc """
  The 8-ball as plain data: shaking it, letting it settle, and the answer
  that floats up.

  Feed `step/2` how far the badge moved since the last tick, as measured by
  `jerk/2`. A ball at rest comes back unchanged, so it costs no repaint.
  Once the shaking has stopped for long enough the ball is `:settled`, and
  `reveal/2` turns it to an answer, which takes a few more ticks to rise
  into full view; `risen/1` says how far it has come.
  """

  # Motion in mg, summed over the three axes, that counts as a shake.
  @shake 300

  # Still ticks before the answer shows.
  @settle 6

  # Ticks the answer takes to rise into full view.
  @rise 8

  # Broken by hand, like the die's faces, so lines narrow toward the triangle's point.
  @answers {
    {["IT IS", "CERTAIN"], :yes},
    {["IT IS", "DECIDEDLY", "SO"], :yes},
    {["WITHOUT", "A DOUBT"], :yes},
    {["YES", "DEFINITELY"], :yes},
    {["YOU MAY", "RELY ON", "IT"], :yes},
    {["AS I SEE IT,", "YES"], :yes},
    {["MOST", "LIKELY"], :yes},
    {["OUTLOOK", "GOOD"], :yes},
    {["YES"], :yes},
    {["SIGNS POINT", "TO YES"], :yes},
    {["REPLY HAZY,", "TRY AGAIN"], :maybe},
    {["ASK AGAIN", "LATER"], :maybe},
    {["BETTER NOT", "TELL YOU", "NOW"], :maybe},
    {["CANNOT", "PREDICT", "NOW"], :maybe},
    {["CONCENTRATE", "AND ASK", "AGAIN"], :maybe},
    {["DON'T", "COUNT", "ON IT"], :no},
    {["MY REPLY", "IS NO"], :no},
    {["MY SOURCES", "SAY NO"], :no},
    {["OUTLOOK", "NOT SO", "GOOD"], :no},
    {["VERY", "DOUBTFUL"], :no}
  }

  @count tuple_size(@answers)

  @type t :: %{
          phase: :idle | :shaking | :settled | :answer,
          still: non_neg_integer,
          wobble: -1 | 0 | 1,
          answer: non_neg_integer | nil,
          rise: non_neg_integer
        }

  @doc "A ball at rest, before the first question."
  @spec new() :: t
  def new, do: %{phase: :idle, still: 0, wobble: 0, answer: nil, rise: 0}

  @doc """
  How far the badge moved between two accelerometer readings, in mg summed
  over the axes. The first reading has nothing to compare against.
  """
  @spec jerk(:undefined | Badge.Accel.mg(), Badge.Accel.mg()) :: non_neg_integer
  def jerk(:undefined, _accel), do: 0
  def jerk({px, py, pz}, {x, y, z}), do: abs(x - px) + abs(y - py) + abs(z - pz)

  @doc "Advances the ball by one tick that moved the badge by `jerk`."
  @spec step(t, non_neg_integer) :: t
  def step(ball, jerk) when jerk >= @shake, do: shaken(ball)

  def step(%{phase: :shaking, still: still} = ball, _jerk) when still + 1 >= @settle,
    do: %{ball | phase: :settled, still: 0, wobble: 0}

  def step(%{phase: :shaking, still: still} = ball, _jerk),
    do: %{ball | still: still + 1, wobble: 0}

  def step(%{phase: :answer, rise: rise} = ball, _jerk) when rise > 0,
    do: %{ball | rise: rise - 1}

  def step(ball, _jerk), do: ball

  @doc "Shakes the ball from a key rather than the accelerometer."
  @spec shake(t) :: t
  def shake(ball), do: shaken(ball)

  defp shaken(%{wobble: 1} = ball), do: %{ball | phase: :shaking, still: 0, wobble: -1}
  defp shaken(ball), do: %{ball | phase: :shaking, still: 0, wobble: 1}

  @doc """
  Shows the answer picked by `roll`, any non-negative integer. The same
  answer never shows twice in a row.
  """
  @spec reveal(t, non_neg_integer) :: t
  def reveal(%{answer: last} = ball, roll) do
    %{
      ball
      | phase: :answer,
        still: 0,
        wobble: 0,
        answer: pick(rem(roll, @count), last),
        rise: @rise
    }
  end

  defp pick(same, same), do: rem(same + 1, @count)
  defp pick(index, _last), do: index

  @doc "How far the answer has risen, in percent: 0 just revealed, 100 in full view."
  @spec risen(t) :: 0..100
  def risen(%{rise: rise}), do: div((@rise - rise) * 100, @rise)

  @doc "The answer's lines, or none unless answering."
  @spec lines(t) :: [binary]
  def lines(%{phase: :answer, answer: index}), do: elem(elem(@answers, index), 0)
  def lines(_ball), do: []

  @doc "The LED hue for the answer's mood: green, amber or red."
  @spec hue(t) :: non_neg_integer
  def hue(%{answer: index}), do: mood_hue(elem(elem(@answers, index), 1))

  defp mood_hue(:yes), do: 120
  defp mood_hue(:maybe), do: 45
  defp mood_hue(:no), do: 0
end
