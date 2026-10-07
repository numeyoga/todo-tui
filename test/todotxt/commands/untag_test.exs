defmodule TodoTxt.Commands.UntagTest do
  use ExUnit.Case, async: true

  alias TodoTxt.{Commands.Untag, Parser}

  @tmp_dir System.tmp_dir!()

  setup do
    dir = Path.join(@tmp_dir, "cmd_untag_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    todo_path = Path.join(dir, "todo.txt")
    File.write!(todo_path, "Buy milk id:10 count:3 min:15\nCall mom due:2026-10-01\n")
    on_exit(fn -> File.rm_rf(dir) end)

    %{todo_path: todo_path}
  end

  test "removes single tag from task", %{todo_path: todo_path} do
    tasks = Parser.parse_all("Buy milk id:10 count:3 min:15\nCall mom due:2026-10-01\n")
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, out} = Untag.run(["2", "due"], ctx)
    refute out =~ "due:2026-10-01"
    assert out =~ "Call mom"
    assert File.read!(todo_path) =~ "Call mom\n"
  end

  test "removes tag with trailing colon", %{todo_path: todo_path} do
    tasks = Parser.parse_all("Buy milk id:10 count:3 min:15\nCall mom due:2026-10-01\n")
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, out} = Untag.run(["2", "due:"], ctx)
    refute out =~ "due:"
  end

  test "removes multiple tags from task", %{todo_path: todo_path} do
    tasks = Parser.parse_all("Buy milk id:10 count:3 min:15\nCall mom due:2026-10-01\n")
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, out} = Untag.run(["1", "id", "count"], ctx)
    refute out =~ "id:10"
    refute out =~ "count:3"
    assert out =~ "min:15"
  end

  test "returns usage on invalid arguments", %{todo_path: todo_path} do
    ctx = %{tasks: [], paths: %{todo: todo_path}, opts: %{}}
    assert {:usage, _} = Untag.run([], ctx)
    assert {:usage, _} = Untag.run(["1"], ctx)
  end

  test "returns error on unknown task number", %{todo_path: todo_path} do
    ctx = %{tasks: [], paths: %{todo: todo_path}, opts: %{}}
    assert {:error, _} = Untag.run(["99", "due"], ctx)
  end
end
