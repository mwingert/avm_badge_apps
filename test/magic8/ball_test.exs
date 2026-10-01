defmodule Badge.App.Magic8.BallTest do
  use ExUnit.Case, async: true

  alias Badge.App.Magic8.Ball

  @flat {0, 0, -1000}

  defp shaken, do: Ball.shake(Ball.new())

  defp still(ball, ticks), do: Enum.reduce(1..ticks, ball, fn _tick, b -> Ball.step(b, 0) end)

  defp settle(ball, ticks \\ 0)
  defp settle(%{phase: :settled} = ball, ticks), do: {ball, ticks}
  defp settle(ball, ticks) when ticks < 50, do: settle(Ball.step(ball, 0), ticks + 1)

  defp answered(roll), do: shaken() |> settle() |> elem(0) |> Ball.reveal(roll)

  defp shown(roll), do: still(answered(roll), 20)

  describe "jerk/2" do
    test "the first reading has nothing to compare against" do
      assert Ball.jerk(:undefined, @flat) == 0
    end

    test "sums the movement on every axis" do
      assert Ball.jerk(@flat, {100, -50, -900}) == 250
      assert Ball.jerk({100, -50, -900}, @flat) == 250
    end
  end

  describe "step/2" do
    test "a ball at rest stays the same term, so nothing repaints" do
      assert Ball.step(Ball.new(), 20) == Ball.new()
      assert Ball.step(shown(3), 20) == shown(3)
    end

    test "a hard jerk shakes it" do
      assert %{phase: :shaking} = Ball.step(Ball.new(), 1000)
      assert %{phase: :shaking} = Ball.step(shown(3), 1000)
    end

    test "the ball wobbles from side to side while it shakes" do
      wobbles =
        Enum.scan(1..4, Ball.new(), fn _tick, b -> Ball.step(b, 1000) end)
        |> Enum.map(& &1.wobble)

      assert wobbles == [1, -1, 1, -1]
    end

    test "keeps shaking for as long as the badge moves" do
      assert %{phase: :shaking} =
               Enum.reduce(1..50, shaken(), fn _tick, b -> Ball.step(b, 1000) end)
    end

    test "settles once the badge has been still for a moment" do
      {settled, ticks} = settle(shaken())

      assert settled.phase == :settled
      assert ticks > 1
      assert %{phase: :shaking, wobble: 0} = still(shaken(), ticks - 1)
    end

    test "a jerk while settling starts the count again" do
      {_settled, ticks} = settle(shaken())
      jolted = shaken() |> still(ticks - 1) |> Ball.step(1000)

      assert %{phase: :shaking} = still(jolted, ticks - 1)
    end
  end

  describe "reveal/2" do
    test "every one of the twenty answers can come up" do
      answers = for roll <- 0..255, uniq: true, do: Ball.lines(answered(roll))

      assert length(answers) == 20
    end

    test "never gives the same answer twice in a row" do
      for roll <- 0..19 do
        first = answered(roll)
        again = first |> Ball.shake() |> settle() |> elem(0) |> Ball.reveal(roll)

        refute Ball.lines(again) == Ball.lines(first)
      end
    end

    test "centres the ball again" do
      assert %{phase: :answer, wobble: 0, still: 0} = answered(7)
    end
  end

  describe "rising" do
    test "a revealed answer rises into full view, then holds still" do
      risen =
        Enum.scan(1..12, answered(3), fn _tick, b -> Ball.step(b, 0) end)
        |> Enum.map(&Ball.risen/1)

      assert Ball.risen(answered(3)) == 0
      assert risen == Enum.sort(risen)
      assert List.last(risen) == 100
      assert Ball.lines(answered(3)) == Ball.lines(shown(3))
    end

    test "a shake while it rises sends it back" do
      assert %{phase: :shaking} = answered(3) |> Ball.step(0) |> Ball.step(1000)
    end
  end

  describe "lines/1" do
    test "nothing shows unless answering" do
      assert Ball.lines(Ball.new()) == []
      assert Ball.lines(shaken()) == []
    end

    test "every answer is one to three lines in capitals, like the die" do
      for roll <- 0..19, lines = Ball.lines(answered(roll)) do
        assert length(lines) in 1..3
        assert Enum.all?(lines, &(&1 == String.upcase(&1)))
      end
    end
  end

  describe "hue/1" do
    test "flashes green, amber or red with the answer's mood" do
      hues = for roll <- 0..19, uniq: true, do: Ball.hue(answered(roll))

      assert Enum.sort(hues) == [0, 45, 120]
    end

    test "a yes is green" do
      roll = Enum.find(0..19, &(Ball.lines(answered(&1)) == ["YES"]))

      assert Ball.hue(answered(roll)) == 120
    end
  end
end
