defmodule TodoTxt.DependenciesTest do
  use ExUnit.Case, async: true

  alias TodoTxt.{Dependencies, Parser}

  test "parse_deps extracts IDs from dep: and p: tags" do
    t1 = Parser.parse("Task dep:101", 1)
    assert Dependencies.parse_deps(t1) == ["101"]

    t2 = Parser.parse("Task p:A,B,C", 2)
    assert Dependencies.parse_deps(t2) == ["A", "B", "C"]

    t3 = Parser.parse("Task without deps", 3)
    assert Dependencies.parse_deps(t3) == []
  end

  test "blocking_tasks identifies pending dependency tasks" do
    t1 = Parser.parse("Parent task id:101", 1)
    t2 = Parser.parse("Child task dep:101", 2)

    assert Dependencies.blocking_tasks(t2, [t1, t2]) == [t1]
    assert Dependencies.blocked?(t2, [t1, t2]) == true

    # When parent task is completed, it no longer blocks
    t1_done = Parser.parse("x 2026-10-07 Parent task id:101", 1)
    assert Dependencies.blocking_tasks(t2, [t1_done, t2]) == []
    assert Dependencies.blocked?(t2, [t1_done, t2]) == false
  end

  test "blocking_tasks falls back to line numbers if id is absent" do
    t1 = Parser.parse("First step", 1)
    t2 = Parser.parse("Second step dep:1", 2)

    assert Dependencies.blocking_tasks(t2, [t1, t2]) == [t1]
  end
end
