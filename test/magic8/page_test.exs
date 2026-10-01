defmodule Badge.App.Magic8.PageTest do
  use ExUnit.Case, async: true

  alias Badge.App.Magic8.Ball
  alias Badge.App.Magic8.Page
  alias Badge.App.Magic8.Shapes
  alias Badge.Theme

  @hint "shake, or press Enter"

  defp answered(roll), do: Ball.reveal(Ball.shake(Page.init()), roll)

  defp frames(roll), do: Enum.scan(1..12, answered(roll), fn _tick, b -> Ball.step(b, 0) end)

  defp shown(roll), do: List.last(frames(roll))

  defp resting, do: Shapes.triangle(Shapes.blue(), 0)

  defp face(ball), do: ball |> rects() |> hd() |> elem(5)

  defp drop(ball), do: elem(hd(rects(ball)), 2) - elem(hd(resting()), 2)

  defp texts(ball), do: for({:text, _x, _y, _f, _fg, _bg, body} <- Page.render(ball), do: body)

  defp rects(ball), do: for({:rect, _x, _y, _w, _h, _c} = rect <- Page.render(ball), do: rect)

  describe "identity" do
    test "fits a home grid cell" do
      assert Page.title() == "Magic 8-Ball"
      assert byte_size(Page.title()) <= 13
    end
  end

  describe "keys" do
    test "Enter and space shake the ball" do
      assert {:ok, %{phase: :shaking}} = Page.handle_key({:edit, :newline}, Page.init())
      assert {:ok, %{phase: :shaking}} = Page.handle_key({:char, ?\s}, answered(2))
    end

    test "every other key is left alone, so Esc and the shape keys still navigate" do
      for event <- [
            {:char, ?a},
            {:move, :up},
            {:edit, :backspace},
            {:nav, :home},
            {:nav, :square}
          ] do
        assert Page.handle_key(event, Page.init()) == :ignore
      end
    end
  end

  describe "render/1" do
    test "shows the 8 at rest, and how to shake it" do
      assert texts(Page.init()) == [@hint]
      assert rects(Page.init()) == Shapes.front()
    end

    test "the 8 wobbles from side to side while shaking" do
      shaking = Ball.shake(Page.init())
      shaken_again = Ball.shake(shaking)

      for {ball, dx} <- [{shaking, 8}, {shaken_again, -8}] do
        assert texts(ball) == [@hint]

        for {{:rect, x, y, w, h, c}, {:rect, x0, y0, w0, h0, c0}} <-
              Enum.zip(rects(ball), Shapes.front()) do
          assert {x - dx, y, w, h, c} == {x0, y0, w0, h0, c0}
        end
      end
    end

    test "an answer shows on the triangle, drawn over it" do
      ball = shown(8)
      items = Page.render(ball)

      assert texts(ball) == Ball.lines(ball)
      assert rects(ball) == resting()

      for {:text, _x, _y, _f, fg, bg, _body} <- Enum.take(items, length(Ball.lines(ball))) do
        assert fg == 0xFFFFFF
        assert bg == Shapes.blue()
      end
    end

    test "every answer sits inside the triangle, clear of its edges" do
      for roll <- 0..19,
          ball <- [answered(roll) | frames(roll)],
          {:text, x, y, _f, _fg, _bg, body} <- Page.render(ball) do
        right = x + byte_size(body) * 8

        for row <- y..(y + 15) do
          assert [{:rect, left_edge, _y, w, _h, _c}] =
                   for(
                     {:rect, _rx, ry, _w, h, _c} = r <- rects(ball),
                     row >= ry and row < ry + h,
                     do: r
                   ),
                 "#{inspect(body)} has no triangle under row #{row}"

          assert x - left_edge >= 4 and left_edge + w - right >= 4,
                 "#{inspect(body)} touches the triangle's edge at row #{row}"
        end
      end
    end

    test "the answer rises out of the background, fading to blue and white" do
      [first | _rest] = all = [answered(5) | frames(5)]
      first_fgs = for {:text, _x, _y, _f, fg, _bg, _body} <- Page.render(first), do: fg

      assert face(first) == Theme.bg()
      assert Enum.uniq(first_fgs) == [Theme.bg()]
      assert drop(first) == Shapes.headroom()

      drops = Enum.map(all, &drop/1)

      assert drops == Enum.sort(drops, :desc)
      assert List.last(drops) == 0
      assert face(List.last(all)) == Shapes.blue()
      assert length(Enum.uniq(Enum.map(all, &face/1))) > 4
    end

    test "fades in from the skin's own background" do
      Badge.Skin.activate(Badge.Skin.Macintosh)

      refute Theme.bg() == 0x000000
      assert face(answered(5)) == Theme.bg()
      assert face(shown(5)) == Shapes.blue()
    after
      Badge.Skin.activate(Badge.Skin.Dark)
    end

    test "draws no background, which the router paints" do
      for ball <- [Page.init(), Ball.shake(Page.init()), answered(0), shown(0)] do
        refute Enum.any?(Page.render(ball), &match?({:rect, 0, 0, _w, _h, _c}, &1))
      end
    end

    test "everything stays on the panel, below the title bar" do
      for roll <- 0..19,
          ball <- [
            answered(roll),
            shown(roll),
            Ball.shake(Page.init()),
            Ball.shake(Ball.shake(Page.init())),
            Page.init()
          ],
          item <- Page.render(ball) do
        {x, y, w, h} = bounds(item)

        assert x >= 0 and x + w <= Theme.width()
        assert y >= Theme.content_top() and y + h <= Theme.height()
      end
    end
  end

  describe "shapes" do
    test "the triangle is equilateral, pointing down" do
      [{:rect, x, top, w, _h, _c} | _rest] = resting()
      {:rect, _x, last, _w, h, _c} = List.last(resting())
      height = last + h - top
      widths = Enum.map(resting(), &elem(&1, 3))

      assert abs(height - round(w * :math.sqrt(3) / 2)) <= 4
      assert x + div(w, 2) == div(Theme.width(), 2)
      assert widths == Enum.sort(widths, :desc)
    end

    test "the 8 is black on a white disc" do
      colours = Shapes.front() |> Enum.map(&elem(&1, 5)) |> Enum.uniq() |> Enum.sort()

      assert colours == [0x000000, 0xFFFFFF]
    end
  end

  defp bounds({:text, x, y, _font, _fg, _bg, body}), do: {x, y, byte_size(body) * 8, 16}
  defp bounds({:rect, x, y, w, h, _c}), do: {x, y, w, h}
end
