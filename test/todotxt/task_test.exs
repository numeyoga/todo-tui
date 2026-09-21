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

  test "recur +1w: next due = completion + 7d" do
    t = Parser.parse("(A) renew +sub due:2026-09-25 recur:+1w", 1)
    n = Task.next_recurrence(t, ~D[2026-09-21])
    assert n.tags["due"] == "2026-09-28"
    assert n.priority == ?A and n.projects == ["+sub"]
    assert n.creation_date == ~D[2026-09-21]
  end

  test "recur 1w strict: next due = old due + 7d" do
    t = Parser.parse("renew due:2026-09-25 recur:1w", 1)
    n = Task.next_recurrence(t, ~D[2026-09-21])
    assert n.tags["due"] == "2026-10-02"
  end

  test "recur without due: base = completion date" do
    t = Parser.parse("water plants recur:+3d", 1)
    assert Task.next_recurrence(t, ~D[2026-09-21]).tags["due"] == "2026-09-24"
  end

  test "no recur tag -> nil; invalid recur -> nil" do
    assert Task.next_recurrence(Parser.parse("x", 1), ~D[2026-09-21]) == nil
    assert Task.next_recurrence(Parser.parse("x recur:banana", 1), ~D[2026-09-21]) == nil
  end
end
