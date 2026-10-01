defmodule Badge.App.Thegoat.RoomTest do
  use ExUnit.Case, async: true

  alias Badge.Chat.Wire
  alias Badge.App.Thegoat.Room

  defp reply(response),
    do: ~s(["1","1","raycaster:lobby","phx_reply",{"status":"ok","response":#{response}}])

  defp snap(players), do: ~s([null,null,"raycaster:lobby","snap",{"p":#{players}}])

  describe "frames to the server" do
    test "join is a Phoenix frame with the ref twice" do
      assert {:ok, %{join_ref: "1", ref: "1", topic: "raycaster:lobby", event: "phx_join"}} =
               Wire.decode_frame(Room.join("1"))
    end

    test "pos carries where the badge stands" do
      assert {:ok, %{topic: "raycaster:lobby", event: "pos", payload: %{"x" => 300, "y" => 400}}} =
               Wire.decode_frame(Room.pos("1", "5", 300, 400))
    end

    test "the heartbeat has no join ref, and the phoenix topic" do
      assert {:ok, %{join_ref: nil, topic: "phoenix", event: "heartbeat"}} =
               Wire.decode_frame(Room.heartbeat())
    end
  end

  describe "interpret/2" do
    test "the answer to a join says the slot" do
      assert Room.interpret(reply(~s({"room":3,"slot":2,"max":8})), nil) == {:joined, 2}
    end

    test "a join answer that makes no sense is ignored" do
      for bad <- [
            ~s({}),
            ~s({"slot":0,"max":8}),
            ~s({"slot":9,"max":8}),
            ~s({"slot":"x","max":8})
          ] do
        assert Room.interpret(reply(bad), nil) == :ignore
      end
    end

    test "a snapshot is everyone else, ready for the engine, in their slot's colour" do
      assert {:players, [{10, 20, c1}, {50, 60, c3}], nil} =
               Room.interpret(snap("[[1,10,20],[2,30,40],[3,50,60]]"), 2)

      assert c1 == Room.colour(1)
      assert c3 == Room.colour(3)
    end

    test "the goat is where the snapshot says, and a server without one has none" do
      with_goat = ~s([null,null,"raycaster:lobby","snap",{"p":[],"g":[900,300,1]}])
      calm = ~s([null,null,"raycaster:lobby","snap",{"p":[],"g":[900,300,0]}])
      none = ~s([null,null,"raycaster:lobby","snap",{"p":[],"g":null}])

      assert Room.interpret(with_goat, 1) == {:players, [], {900, 300, true}}
      assert Room.interpret(calm, 1) == {:players, [], {900, 300, false}}
      assert Room.interpret(none, 1) == {:players, [], nil}
    end

    test "a goat outside the map, or in the wrong shape, refuses the snapshot" do
      for goat <- ["[9999,300,1]", "[-1,300,1]", "[900,300,2]", "[900,300]", ~s("goat"), "1.5"] do
        frame = ~s([null,null,"raycaster:lobby","snap",{"p":[],"g":#{goat}}])
        assert Room.interpret(frame, nil) == :ignore
      end
    end

    test "caught is told on the lobby topic only" do
      assert Room.interpret(~s([null,null,"raycaster:lobby","caught",{}]), 1) == :caught
      assert Room.interpret(~s([null,null,"chat:lobby","caught",{}]), 1) == :ignore
    end

    test "respawn is a Phoenix frame with the join ref" do
      assert Room.respawn("1", "7") == ~s(["1","7","raycaster:lobby","respawn",{}])
    end

    test "leave is a Phoenix frame with the join ref" do
      assert Room.leave("1", "8") == ~s(["1","8","raycaster:lobby","phx_leave",{}])
    end

    test "an empty room is an empty list, not an error" do
      assert Room.interpret(snap("[]"), 1) == {:players, [], nil}
    end

    test "a snapshot with anything odd in it is refused whole" do
      for bad <- [
            ~s([[1,10]]),
            ~s([[1,"a",2]]),
            ~s([[0,1,2]]),
            ~s([[1,-1,2]]),
            ~s([[1,4096,2]]),
            ~s([[1.5,1,2]]),
            ~s(["x"])
          ] do
        assert Room.interpret(snap(bad), nil) == :ignore
      end
    end

    test "more players than a room holds is not a room" do
      many = "[" <> Enum.map_join(1..17, ",", fn n -> "[#{n},1,1]" end) <> "]"

      assert Room.interpret(snap(many), nil) == :ignore
    end

    test "whatever else arrives is ignored" do
      for junk <- [
            "",
            "not json",
            "{}",
            "[1]",
            ~s([null,null,"chat:lobby","snap",{"p":[]}]),
            ~s([null,null,"raycaster:lobby","other",{}])
          ] do
        assert Room.interpret(junk, nil) == :ignore
      end
    end
  end

  test "each slot of a room has its own colour, and they wrap after eight" do
    colours = for slot <- 1..8, do: Room.colour(slot)

    assert length(Enum.uniq(colours)) == 8
    assert Room.colour(9) == Room.colour(1)
  end
end
