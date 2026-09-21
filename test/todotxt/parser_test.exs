defmodule TodoTxt.ParserTest do
  use ExUnit.Case
  alias TodoTxt.Parser

  test "simple task" do
    t = Parser.parse("call mom", 1)
    assert t.line == 1 and t.description == "call mom"
    refute t.done
    assert t.priority == nil
  end

  test "priority + creation date" do
    t = Parser.parse("(A) 2026-09-20 call mom +family @phone due:2026-09-25", 2)
    assert t.priority == ?A
    assert t.creation_date == ~D[2026-09-20]
    assert t.projects == ["+family"]
    assert t.contexts == ["@phone"]
    assert t.tags == %{"due" => "2026-09-25"}
  end

  test "done task with completion and creation dates" do
    t = Parser.parse("x 2026-09-21 2026-09-20 call mom +family", 3)
    assert t.done and t.completion_date == ~D[2026-09-21]
    assert t.creation_date == ~D[2026-09-20]
    assert t.priority == nil
  end

  test "x alone marks done; x as a word still marks done per spec" do
    assert Parser.parse("x marks the spot", 1).done
  end

  test "(A) not at head stays literal" do
    t = Parser.parse("call mom (A)", 1)
    assert t.priority == nil
    assert t.description =~ "(A)"
  end

  test "urls are not tags" do
    t = Parser.parse("read http://example.com docs", 1)
    assert t.tags == %{}
  end

  test "parse_all: CRLF, no trailing newline, blank lines keep real line numbers" do
    t = Parser.parse_all("first\r\n\r\nsecond")
    assert Enum.map(t, & &1.line) == [1, 3]
  end
end
