defmodule TodoTxt.TaskTest do
  use ExUnit.Case
  alias TodoTxt.{Parser, Task}

  test "render round-trips a parsed line" do
    for line <- [
          "(A) 2026-09-20 call mom +f @p due:2026-09-25",
          "x 2026-09-21 2026-09-20 done thing",
          "plain task"
        ] do
      assert Parser.render(Parser.parse(line, 1)) == line
    end
  end

  test "complete drops priority and sets completion date" do
    t = Parser.parse("(B) 2026-09-20 call mom", 1) |> Task.complete(~D[2026-09-21])
    assert Parser.render(t) == "x 2026-09-21 2026-09-20 call mom"
  end

  test "uncomplete strips x and completion date" do
    t = Parser.parse("x 2026-09-21 call mom", 1) |> Task.uncomplete()
    assert Parser.render(t) == "call mom"
  end

  test "set_priority and append/prepend" do
    t = Parser.parse("call mom", 1)
    assert t |> Task.set_priority(?C) |> Parser.render() == "(C) call mom"
    assert t |> Task.append_text("+fam") |> Parser.render() == "call mom +fam"
    assert t |> Task.prepend_text("please") |> Parser.render() == "please call mom"
  end
end
