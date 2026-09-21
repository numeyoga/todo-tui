defmodule TodoTxt.FormatTest do
  use ExUnit.Case

  alias TodoTxt.{Format, Parser}

  @plain %{plain: true}

  test "tasks renders 'N: raw' lines" do
    ts = Parser.parse_all("plain\n(B) b")
    assert Format.tasks(ts, @plain) == "1: plain\n2: (B) b"
  end

  test "tasks returns empty string for no tasks" do
    assert Format.tasks([], @plain) == ""
  end

  test "tasks colorizes by priority and done when colors enabled" do
    System.put_env("TERM", "xterm-256color")
    System.delete_env("NO_COLOR")

    out = Format.tasks(Parser.parse_all("(A) a\nx done"), %{plain: false})
    assert out =~ IO.ANSI.red()
    assert out =~ IO.ANSI.faint()
    assert out =~ "1: (A) a"
    assert out =~ "2: x done"
  end

  test "plain mode emits no ANSI even when colors would be enabled" do
    System.put_env("TERM", "xterm-256color")
    System.delete_env("NO_COLOR")

    refute Format.tasks(Parser.parse_all("(A) a"), @plain) =~ "\e["
  end

  test "NO_COLOR disables colors" do
    System.put_env("TERM", "xterm-256color")
    System.put_env("NO_COLOR", "1")

    refute Format.tasks(Parser.parse_all("(A) a"), %{plain: false}) =~ "\e["
  after
    System.delete_env("NO_COLOR")
  end

  test "task_map returns a JSON-encodable map" do
    [t] = Parser.parse_all("x 2026-09-20 2026-09-01 call mom +fam @home k:v")
    m = Format.task_map(t)

    assert m.line == 1
    assert m.done == true
    assert is_nil(m.priority)
    assert m.completion_date == "2026-09-20"
    assert m.creation_date == "2026-09-01"
    assert m.description == "call mom +fam @home k:v"
    assert m.projects == ["+fam"]
    assert m.contexts == ["@home"]
    assert m.tags == %{"k" => "v"}
    assert is_binary(Jason.encode!(m))
  end
end
