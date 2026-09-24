defmodule TodoTxt.TasksTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Parser, Tasks}

  @paths %{todo: "t", done: "d"}
  @today ~D[2026-09-21]

  defp t(raw, line), do: Parser.parse(raw, line)

  # Records every io call, in order, as messages to the test process.
  defp io(overrides \\ %{}) do
    pid = self()

    Map.merge(
      %{
        read: fn p -> send(pid, {:read, p}) && {:ok, []} end,
        write: fn p, ts -> send(pid, {:write, p, ts}) && :ok end,
        append: fn p, ts -> send(pid, {:append, p, ts}) && :ok end
      },
      overrides
    )
  end

  test "complete writes once, recurrence numbered next_line at the end" do
    tasks = [t("r recur:1d due:2026-09-22", 1), t("b", 4)]
    assert {:ok, r} = Tasks.complete(io(), @paths, tasks, hd(tasks), @today)
    assert r.task.done and r.recur.line == 5
    assert List.last(r.tasks) == r.recur
    assert_received {:write, "t", written}
    assert written == r.tasks
    refute_received {:append, _, _}
  end

  test "complete with malformed recur errors before any io" do
    tasks = [t("r recur:bad", 1)]
    assert {:error, m} = Tasks.complete(io(), @paths, tasks, hd(tasks), @today)
    assert m =~ "invalid recur"
    refute_received {:write, _, _}
  end

  test "move appends to dest before rewriting src; failed append writes nothing" do
    tasks = [t("a", 1), t("b", 2)]
    assert {:ok, %{tasks: [%{line: 2}]}} = Tasks.move(io(), "t", "d", tasks, hd(tasks))
    assert_received {:append, "d", [%{line: 1}]}
    assert_received {:write, "t", [%{line: 2}]}

    failing = io(%{append: fn _, _ -> {:error, "disk full"} end})
    assert {:error, "disk full"} = Tasks.move(failing, "t", "d", tasks, hd(tasks))
    refute_received {:write, _, _}
  end

  test "reopen appends the uncompleted task to todo, rewrites done without it" do
    done = [t("x 2026-09-20 fini", 7)]
    assert {:ok, %{done_tasks: [], task: reopened}} = Tasks.reopen(io(), @paths, done, hd(done))
    refute reopened.done
    assert_received {:append, "t", [^reopened]}
    assert_received {:write, "d", []}
  end

  test "archive skips the done append when nothing is done" do
    assert {:ok, %{count: 0}} = Tasks.archive(io(), @paths, [t("a", 1)])
    refute_received {:append, _, _}
    assert_received {:write, "t", [_]}

    assert {:ok, %{count: 1, tasks: [%{line: 1}]}} =
             Tasks.archive(io(), @paths, [t("a", 1), t("x done", 2)])

    assert_received {:append, "d", [%{line: 2}]}
  end

  test "add appends a dated task at next_line" do
    assert {:ok, %{task: task, tasks: [_, task]}} =
             Tasks.add(io(), @paths, [t("a", 3)], "hi", @today)

    assert task.line == 4 and task.creation_date == @today
    assert_received {:append, "t", [^task]}
  end

  test "single-list wrappers write the given path and return the updated task" do
    tasks = [t("a", 1)]
    assert {:ok, %{task: %{priority: ?B}}} = Tasks.set_priority(io(), "d", tasks, hd(tasks), ?B)
    assert_received {:write, "d", _}

    assert {:error, _} = Tasks.set_priority(io(), "t", tasks, hd(tasks), ?1)
    refute_received {:write, _, _}
  end

  test "load reads both files and surfaces read errors" do
    assert {:ok, %{tasks: [], done_tasks: []}} = Tasks.load(io(), @paths)

    failing = io(%{read: fn _ -> {:error, "nope"} end})
    assert {:error, "nope"} = Tasks.load(failing, @paths)
  end
end
