# Copied from raycaster/test/engine_test.exs without its "fixed tour" block,
# which needs Raycaster.Bench and the pinned frames; those run in that project.
defmodule Badge.App.Thegoat.EngineTest do
  # The engine is plain integer arithmetic, so it can be checked on the laptop
  # with `mix test`; only the display and keyboard need the badge.
  use ExUnit.Case, async: true

  alias Badge.App.Thegoat.Engine

  @width 320
  @height 240
  @ceiling 0x202838
  @floor 0x504030

  # The player starts in the corner cell (1.5, 1.5), and one map cell is 256.
  @cell 256

  defp frame(player), do: Engine.frame(Engine.grid(), player, @width, @height)

  defp walls(items),
    do: for({:rect, x, y, w, h, c} <- items, c not in [@ceiling, @floor], do: {x, y, w, h})

  # The wall rectangle covering the middle of the screen, which is where the
  # ray runs straight along the player's direction.
  defp centre_wall(player) do
    Enum.find(walls(frame(player)), fn {x, _y, w, _h} -> x <= 160 and 160 < x + w end)
  end

  describe "wall height in the middle column is screen height / distance" do
    test "facing the west wall half a cell away fills the screen" do
      # Height would be 480, clamped to the screen.
      assert {_x, 0, _w, 240} = centre_wall(%{Engine.new() | a: 128 * 256})
    end

    test "facing the far east wall 13.5 cells away" do
      # 240 * 256 / (13.5 * 256), rounded down.
      assert {_x, top, _w, 17} = centre_wall(%{Engine.new() | a: 0})
      assert top == div(240 - 17, 2)
    end

    test "standing closer makes the same wall taller" do
      near = %{x: 12 * @cell + 128, y: 384, a: 0}

      # 2.5 cells to the wall at x = 15: 240 * 256 / 640 = 96.
      assert {_x, _top, _w, 96} = centre_wall(near)
    end

    test "looking along y gives the same distance as along x" do
      assert {_, _, _, 17} = centre_wall(%{Engine.new() | a: 64 * 256})
    end
  end

  describe "frame/4" do
    test "everything stays on the screen and the list stays small" do
      for x <- [1, 5, 8, 14], y <- [1, 6, 13], a <- [0, 37, 90, 150, 222] do
        items = frame(%{x: x * @cell + 100, y: y * @cell + 100, a: a * 256})

        for {:rect, rx, ry, w, h, _colour} <- items do
          assert rx >= 0 and ry >= 0 and w > 0 and h > 0
          assert rx + w <= @width and ry + h <= @height
        end

        # At most one rectangle per column, plus floor and ceiling.
        assert length(items) <= Engine.cols() + 2
      end
    end

    test "floor and ceiling are drawn behind the walls" do
      items = frame(Engine.new())

      # The first item is on top and the last is drawn first.
      assert [{:rect, 0, 0, @width, 120, @ceiling}, {:rect, 0, 120, @width, 120, @floor} | _] =
               Enum.reverse(items)
    end

    test "farther walls are darker" do
      colour_at = fn a ->
        {:rect, _x, _y, _w, _h, colour} =
          Enum.find(frame(%{Engine.new() | a: a}), fn {:rect, x, _, w, _, c} ->
            c not in [@ceiling, @floor] and x <= 160 and 160 < x + w
          end)

        colour
      end

      brightness = fn c ->
        Bitwise.band(c, 0xFF) + Bitwise.band(Bitwise.bsr(c, 8), 0xFF) + Bitwise.bsr(c, 16)
      end

      # West wall is 0.5 cells away, east wall 13.5.
      assert brightness.(colour_at.(128 * 256)) > brightness.(colour_at.(0))
    end
  end

  describe "the map" do
    # Rays are not bounds checked and have no step limit: the outer wall is what
    # stops them.
    test "is closed all the way round" do
      grid = Engine.grid()
      border = for i <- 0..15, cell <- [{i, 0}, {i, 15}, {0, i}, {15, i}], uniq: true, do: cell

      for {x, y} <- border do
        assert elem(grid, y * 16 + x) != 0, "open border cell at #{x},#{y}"
      end
    end
  end

  describe "step/4" do
    test "holding forward moves along the direction" do
      moved = Engine.step(Engine.grid(), Engine.new(), [~c"Up"], 200)

      assert moved.x > Engine.new().x
      assert moved.y == Engine.new().y
    end

    test "turning changes only the angle, at a rate that does not depend on frame time" do
      one = Engine.step(Engine.grid(), Engine.new(), [~c"Right"], 1000)

      halves =
        Enum.reduce(1..10, Engine.new(), fn _, p ->
          Engine.step(Engine.grid(), p, [~c"Right"], 100)
        end)

      assert one.a == 40_000
      assert halves.a == 40_000
      assert {one.x, one.y} == {Engine.new().x, Engine.new().y}
    end

    test "walls stop the player, on each axis separately" do
      grid = Engine.grid()
      # Facing west, into the wall column x = 0, for long enough to cross it.
      west =
        Enum.reduce(1..50, %{Engine.new() | a: 128 * 256}, fn _, p ->
          Engine.step(grid, p, [~c"Up"], 100)
        end)

      # Never inside the wall cell (x < 256), with room for the player's radius.
      assert west.x >= @cell + 60

      # Walking diagonally into the corner slides along a wall instead of sticking.
      corner = %{x: @cell + 100, y: 2 * @cell, a: 96 * 256}
      slid = Enum.reduce(1..20, corner, fn _, p -> Engine.step(grid, p, [~c"Up"], 100) end)

      assert slid.x >= @cell + 60
      assert slid.y != corner.y
    end

    test "no keys held means no movement" do
      assert Engine.step(Engine.grid(), Engine.new(), [], 500) == Engine.new()
    end
  end

  describe "respawn/1" do
    test "without a goat it is the start, as a new player" do
      assert Engine.respawn(nil) == Engine.new()
    end

    test "a goat near the start sends the badge to the far corner, facing north" do
      assert %{x: 3456, y: 3456, a: 49_152} = Engine.respawn({500, 500, true})
    end

    test "a goat near the far corner leaves the badge at the start" do
      assert Engine.respawn({3400, 3400, false}) == Engine.new()
    end

    test "it is the same whether the goat is hunting or wandering" do
      assert Engine.respawn({500, 500, true}) == Engine.respawn({500, 500, false})
    end

    test "either place looks down a corridor, not at a wall" do
      # A wall half a cell away is 240 pixels tall and fills the screen; 8 cells away it is 30.
      for goat <- [{500, 500, true}, {3400, 3400, true}] do
        assert {_x, _top, _w, height} = centre_wall(Engine.respawn(goat))
        assert height <= 30
      end
    end

    test "either place is open floor" do
      grid = Engine.grid()

      for goat <- [{500, 500, true}, {3400, 3400, true}] do
        %{x: x, y: y} = Engine.respawn(goat)
        assert elem(grid, div(y, 256) * 16 + div(x, 256)) == 0
      end
    end
  end
end
