defmodule TodoTxt.Commands.TagTest do
  use ExUnit.Case, async: true

  alias TodoTxt.{Commands.Tag, Parser}

  @tmp_dir System.tmp_dir!()

  setup do
    dir = Path.join(@tmp_dir, "cmd_tag_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    todo_path = Path.join(dir, "todo.txt")
    File.write!(todo_path, "Buy milk\nCall mom due:2026-10-01\n")
    on_exit(fn -> File.rm_rf(dir) end)

    %{todo_path: todo_path}
  end

  test "adds key value tag with two arguments", %{todo_path: todo_path} do
    tasks = Parser.parse_all("Buy milk\nCall mom due:2026-10-01\n")
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, out} = Tag.run(["1", "due", "2026-10-15"], ctx)
    assert out =~ "due:2026-10-15"
    assert File.read!(todo_path) =~ "due:2026-10-15"
  end

  test "adds single key:value tag argument", %{todo_path: todo_path} do
    tasks = Parser.parse_all("Buy milk\nCall mom due:2026-10-01\n")
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, out} = Tag.run(["1", "id:42"], ctx)
    assert out =~ "id:42"
    assert File.read!(todo_path) =~ "id:42"
  end

  test "adds multiple key:value tags", %{todo_path: todo_path} do
    tasks = Parser.parse_all("Buy milk\nCall mom due:2026-10-01\n")
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, out} = Tag.run(["1", "id:99", "count:5", "min:30"], ctx)
    assert out =~ "id:99"
    assert out =~ "count:5"
    assert out =~ "min:30"
  end

  test "updates existing tag", %{todo_path: todo_path} do
    tasks = Parser.parse_all("Buy milk\nCall mom due:2026-10-01\n")
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, out} = Tag.run(["2", "due", "2026-11-20"], ctx)
    assert out =~ "due:2026-11-20"
    refute out =~ "due:2026-10-01"
  end

  test "returns usage on invalid arguments", %{todo_path: todo_path} do
    ctx = %{tasks: [], paths: %{todo: todo_path}, opts: %{}}
    assert {:usage, _} = Tag.run([], ctx)
    assert {:usage, _} = Tag.run(["1"], ctx)
  end

  test "returns error on unknown task number", %{todo_path: todo_path} do
    ctx = %{tasks: [], paths: %{todo: todo_path}, opts: %{}}
    assert {:error, _} = Tag.run(["99", "due", "2026-10-15"], ctx)
  end
end
