defmodule TodoTxt.Commands.MinTest do
  use ExUnit.Case, async: true

  alias TodoTxt.{Commands.Min, Parser}

  @tmp_dir System.tmp_dir!()

  setup do
    dir = Path.join(@tmp_dir, "cmd_min_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    todo_path = Path.join(dir, "todo.txt")
    File.write!(todo_path, "Task 1\nTask 2 min:30\n")
    on_exit(fn -> File.rm_rf(dir) end)

    %{todo_path: todo_path}
  end

  test "sets absolute minutes on task without min tag", %{todo_path: todo_path} do
    tasks = Parser.parse_all("Task 1\nTask 2 min:30\n")
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, out} = Min.run(["1", "45"], ctx)
    assert out =~ "min:45"
    assert out =~ "45m"
  end

  test "adds relative minutes with +prefix", %{todo_path: todo_path} do
    tasks = Parser.parse_all("Task 1\nTask 2 min:30\n")
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, out} = Min.run(["2", "+15"], ctx)
    assert out =~ "min:45"
  end

  test "subtracts relative minutes with -prefix", %{todo_path: todo_path} do
    tasks = Parser.parse_all("Task 1\nTask 2 min:30\n")
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, out} = Min.run(["2", "-10"], ctx)
    assert out =~ "min:20"
  end

  test "returns usage on invalid arguments", %{todo_path: todo_path} do
    ctx = %{tasks: [], paths: %{todo: todo_path}, opts: %{}}
    assert {:usage, _} = Min.run([], ctx)
  end
end
