defmodule Badge.App.Magic8.Shapes do
  @moduledoc """
  The two faces of the ball as AtomGL rects, worked out on the host at
  compile time: the white disc with its 8, and the blue triangle an answer
  floats up on. Curves and slopes are drawn in strips four pixels tall.

  The triangle takes its colour and a downward offset, so an answer can
  fade and rise into view.
  """

  @strip 4
  @white 0xFFFFFF
  @black 0x000000
  @blue 0x2450D8

  @cx 160
  @disc_y 116
  @tri_top 32
  @tri_side 222
  @tri_height 192

  disc = fn cx, cy, r, colour ->
    for y <- (cy - r)..(cy + r - 1)//@strip,
        dy = y + div(@strip, 2) - cy,
        dy * dy < r * r do
      half = round(:math.sqrt(r * r - dy * dy))
      {:rect, cx - half, y, 2 * half, @strip, colour}
    end
  end

  # Head first: the 8's holes, the 8, the disc, then an outline for light skins.
  @front disc.(@cx, @disc_y - 22, 10, @white) ++
           disc.(@cx, @disc_y + 20, 13, @white) ++
           disc.(@cx, @disc_y - 22, 22, @black) ++
           disc.(@cx, @disc_y + 20, 26, @black) ++
           disc.(@cx, @disc_y, 80, @white) ++
           disc.(@cx, @disc_y, 82, @black)

  @strips (for i <- 0..(div(@tri_height, @strip) - 1) do
             d = i * @strip + div(@strip, 2)
             half = round(@tri_side * (@tri_height - d) / (2 * @tri_height))
             {@cx - half, @tri_top + i * @strip, 2 * half}
           end)

  @doc "The white disc with the 8 on it."
  def front, do: @front

  @doc "The triangle, pointing down, in `colour` and `dy` pixels below its resting place."
  def triangle(colour, dy),
    do: :lists.map(fn {x, y, w} -> {:rect, x, y + dy, w, @strip, colour} end, @strips)

  @doc "How far below its resting place the triangle can sit and stay on the panel."
  def headroom, do: Badge.Theme.height() - (@tri_top + @tri_height)

  @doc "The triangle's colour in full view."
  def blue, do: @blue

  @doc "The row the triangle's centroid sits on, for centring an answer."
  def centre_y, do: @tri_top + div(@tri_height, 3)
end
