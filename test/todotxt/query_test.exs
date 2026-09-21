defmodule TodoTxt.QueryTest do
  use ExUnit.Case

  alias TodoTxt.{Parser, Query}

  test "sort: priority then line, no-priority last" do
    ts = Parser.parse_all("plain\n(B) b\n(A) a")
    assert Enum.map(Query.sort(ts), & &1.line) == [3, 2, 1]
  end

  test "filter: terms AND, +p exact, substring" do
    ts = Parser.parse_all("call mom +fam\ncall dad\nx done +fam")
    assert Enum.map(Query.filter(ts, ["+fam"]), & &1.line) == [1, 3]
    assert Enum.map(Query.filter(ts, ["mom"]), & &1.line) == [1]
    assert Query.filter(ts, ["dad", "+fam"]) == []
  end

  test "filter: @c is an exact context token" do
    ts = Parser.parse_all("a @home\nb @homeoffice")
    assert Enum.map(Query.filter(ts, ["@home"]), & &1.line) == [1]
  end

  test "visible hides future t: threshold, shows reached" do
    ts = Parser.parse_all("later t:2026-10-01\nnow t:2026-09-01\nplain\nx done t:2099-01-01")
    assert Enum.map(Query.visible(ts, ~D[2026-09-21]), & &1.line) == [2, 3, 4]
  end
end
