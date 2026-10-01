defmodule Badge.App.Eliza.PageTest do
  use ExUnit.Case, async: true

  alias Badge.App.Eliza.Eliza
  alias Badge.App.Eliza.Page
  alias Badge.Theme

  defp type(state, string) do
    :lists.foldl(
      fn char, acc ->
        {:ok, next} = Page.handle_key({:char, char}, acc)
        next
      end,
      state,
      :erlang.binary_to_list(string)
    )
  end

  defp say(state, string) do
    {:ok, next} = Page.handle_key({:edit, :newline}, type(state, string))
    next
  end

  defp texts(items) do
    for {:text, _x, _y, _font, _fg, _bg, body} <- items, do: body
  end

  defp draft(items) do
    [line] = for {:text, _x, 214, _font, _fg, _bg, body} <- items, do: body
    line
  end

  describe "identity" do
    test "announces itself for the apps grid" do
      assert Page.title() == "Eliza"
    end
  end

  describe "init/0" do
    test "opens with the greeting and an empty draft" do
      items = Page.render(Page.init())

      assert hd(texts(items)) == "How do you do. Please tell me your"
      assert draft(items) == "> _"
    end
  end

  describe "typing" do
    test "characters land in the draft with the caret after them" do
      assert draft(Page.render(type(Page.init(), "hi"))) == "> hi_"
    end

    test "backspace removes the last character" do
      {:ok, state} = Page.handle_key({:edit, :backspace}, type(Page.init(), "hi"))

      assert draft(Page.render(state)) == "> h_"
    end

    test "left and right move the caret inside the draft" do
      {:ok, state} = Page.handle_key({:move, :left}, type(Page.init(), "hi"))

      assert draft(Page.render(state)) == "> h_i"

      {:ok, state} = Page.handle_key({:move, :right}, state)

      assert draft(Page.render(state)) == "> hi_"
    end

    test "a long draft scrolls under the caret rather than off the panel" do
      long = :erlang.list_to_binary(:lists.duplicate(60, ?a))
      line = draft(Page.render(type(Page.init(), long)))

      assert byte_size(line) == 38
      assert :binary.last(line) == ?_
    end

    test "enter on an empty draft is left for the router" do
      assert Page.handle_key({:edit, :newline}, Page.init()) == :ignore
    end
  end

  describe "conversation" do
    test "enter posts the line, appends the reply and clears the draft" do
      state = say(Page.init(), "Men are all alike")

      assert [{:eliza, "In what way?"}, {:you, "> Men are all alike"} | _rest] =
               Page.lines(state)

      assert draft(Page.render(state)) == "> _"
    end

    test "the reply comes from Eliza's own state, so answers cycle" do
      state = Page.init() |> say("yes") |> say("yes")

      assert [{:eliza, "You are sure."} | _rest] = Page.lines(state)
    end

    test "long lines wrap to the panel width" do
      state = say(Page.init(), "I am unhappy because nothing I do ever seems to work out well")

      for {_who, line} <- Page.lines(state) do
        assert byte_size(line) <= 38
      end
    end

    test "a goodbye starts a fresh conversation" do
      state = Page.init() |> say("yes") |> say("bye") |> say("yes")

      assert [{:eliza, "You seem to be quite positive."} | _rest] = Page.lines(state)
      assert Eliza.farewell?(elem(:lists.nth(3, Page.lines(state)), 1))
    end

    test "keeps only the newest lines" do
      state = :lists.foldl(fn _n, acc -> say(acc, "yes") end, Page.init(), :lists.seq(1, 50))

      assert length(Page.lines(state)) <= 64
    end
  end

  describe "scrolling" do
    setup do
      {:ok,
       state: :lists.foldl(fn _n, acc -> say(acc, "yes") end, Page.init(), :lists.seq(1, 6))}
    end

    test "up shows older lines and hides the caret", %{state: state} do
      {:ok, scrolled} = Page.handle_key({:move, :up}, state)

      assert hd(texts(Page.render(scrolled))) != hd(texts(Page.render(state)))
      assert draft(Page.render(scrolled)) == "> "
    end

    test "down comes back, and at the newest line is left for the router", %{state: state} do
      {:ok, scrolled} = Page.handle_key({:move, :up}, state)
      {:ok, back} = Page.handle_key({:move, :down}, scrolled)

      assert Page.render(back) == Page.render(state)
      assert Page.handle_key({:move, :down}, back) == :ignore
    end

    test "up stops at the oldest line", %{state: state} do
      last =
        :lists.foldl(
          fn _n, acc ->
            case Page.handle_key({:move, :up}, acc) do
              {:ok, next} -> next
              :ignore -> acc
            end
          end,
          state,
          :lists.seq(1, 40)
        )

      assert Page.handle_key({:move, :up}, last) == :ignore
      assert hd(texts(Page.render(last))) == "How do you do. Please tell me your"
    end

    test "typing brings the newest line back", %{state: state} do
      {:ok, scrolled} = Page.handle_key({:move, :up}, state)
      typed = type(scrolled, "a")

      assert draft(Page.render(typed)) == "> a_"
    end

    test "with nothing to scroll to, up is left for the router" do
      assert Page.handle_key({:move, :up}, Page.init()) == :ignore
    end
  end

  describe "render/1" do
    test "every item sits inside the content area" do
      state = :lists.foldl(fn _n, acc -> say(acc, "yes") end, Page.init(), :lists.seq(1, 6))

      for item <- Page.render(state) do
        y =
          case item do
            {:rect, _x, y, _w, _h, _c} -> y
            {:text, _x, y, _f, _fg, _bg, _b} -> y
          end

        assert y >= Theme.content_top()
        assert y < Theme.height()
      end
    end

    test "shows at most eight transcript rows" do
      state = :lists.foldl(fn _n, acc -> say(acc, "yes") end, Page.init(), :lists.seq(1, 6))
      rows = for {:text, _x, y, _f, _fg, _bg, _b} <- Page.render(state), y < 206, do: y

      assert length(rows) == 8
    end

    test "does not trap escape" do
      assert Page.handle_key({:nav, :home}, Page.init()) == :ignore
    end
  end
end
