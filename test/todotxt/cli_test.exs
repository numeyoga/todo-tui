defmodule TodoTxt.CLITest do
  use ExUnit.Case

  alias TodoTxt.{CLI, Store}

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ttcli#{System.system_time(:nanosecond)}#{System.unique_integer([:positive])}"
      )

    env = %{
      paths: %{
        todo: Path.join(dir, "todo.txt"),
        done: Path.join(dir, "done.txt"),
        report: Path.join(dir, "report.txt")
      },
      today: ~D[2026-09-21]
    }

    %{env: env, dir: dir}
  end

  test "add appends with creation date and echoes line", %{env: e} do
    assert {:ok, out} = TodoTxt.CLI.run(["add", "call", "mom", "+fam"], e)
    assert out =~ "1:"
    {:ok, [t]} = TodoTxt.Store.read(e.paths.todo)
    assert t.creation_date == ~D[2026-09-21]
    assert t.projects == ["+fam"]
  end

  test "add without args is a usage error", %{env: e} do
    assert {:usage, _} = TodoTxt.CLI.run(["add"], e)
  end

  test "ls lists sorted with stable line numbers", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "plain\n(B) b\n(A) a t:2099-01-01\n")
    # note: t:2099 hidden -> only lines 1,2 shown; (B) before plain
    assert {:ok, out} = TodoTxt.CLI.run(["--plain", "ls"], e)
    assert out == "2: (B) b\n1: plain"
  end

  test "ls filters by terms", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "call mom +fam\ncall dad\n")
    assert {:ok, out} = TodoTxt.CLI.run(["--plain", "ls", "+fam"], e)
    assert out == "1: call mom +fam"
  end

  test "list alias works like ls", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "plain\n(A) a\n")
    assert {:ok, out} = TodoTxt.CLI.run(["--plain", "list"], e)
    assert out == "2: (A) a\n1: plain"
  end

  test "unknown command is a usage error", %{env: e} do
    assert {:usage, m} = TodoTxt.CLI.run(["bogus"], e)
    assert m =~ "bogus"
  end

  test "do marks done with today, drops priority", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "(A) call mom\nother\n")
    assert {:ok, _} = CLI.run(["do", "1"], e)
    assert {:ok, [t1, _]} = Store.read(e.paths.todo)
    assert t1.done and t1.completion_date == ~D[2026-09-21] and t1.priority == nil
  end

  test "do on bad number and on already-done", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "x 2026-01-01 done\n")
    assert {:error, m} = CLI.run(["do", "9"], e)
    assert m =~ "9"
    assert {:error, _} = CLI.run(["do", "abc"], e)
  end

  test "do on a recurring task appends the next occurrence", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "renew due:2026-09-25 recur:+1w\n")
    assert {:ok, out} = CLI.run(["do", "1"], e)
    assert out =~ "2: 2026-09-21 renew due:2026-09-28 recur:+1w"
    assert {:ok, [_, new]} = Store.read(e.paths.todo)
    assert new.tags["due"] == "2026-09-28" and not new.done
  end

  test "do recurrence gets a line number past the max, not task count", %{
    env: e,
    dir: dir
  } do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "a\n\nrecur me recur:+1d\n")
    assert {:ok, out} = CLI.run(["do", "3"], e)
    assert out =~ "4: 2026-09-21 recur me recur:+1d due:2026-09-22"
    {:ok, tasks} = Store.read(e.paths.todo)
    assert List.last(tasks).tags["due"] == "2026-09-22"
  end

  test "undo reopens", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "x 2026-09-21 task\n")
    {:ok, _} = CLI.run(["undo", "1"], e)
    {:ok, [t]} = Store.read(e.paths.todo)
    refute t.done
  end

  test "del removes line; del N TERM strips term", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "one\ntwo +p\n")
    {:ok, _} = CLI.run(["del", "2", "+p"], e)
    {:ok, [_, t]} = Store.read(e.paths.todo)
    assert t.raw == "two"
    {:ok, _} = CLI.run(["del", "1"], e)
    assert {:ok, [t]} = Store.read(e.paths.todo)
    assert t.raw == "two"
  end

  test "pri/depri/append/prepend/replace", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "call mom\n")
    {:ok, _} = CLI.run(["pri", "1", "B"], e)
    {:ok, [t]} = Store.read(e.paths.todo)
    assert t.priority == ?B
    {:ok, _} = CLI.run(["depri", "1"], e)
    {:ok, [t]} = Store.read(e.paths.todo)
    assert t.priority == nil
    {:ok, _} = CLI.run(["append", "1", "+fam"], e)
    {:ok, _} = CLI.run(["prepend", "1", "please"], e)
    {:ok, [t]} = Store.read(e.paths.todo)
    assert t.raw == "please call mom +fam"
    {:ok, _} = CLI.run(["replace", "1", "new", "text", "+p"], e)
    {:ok, [t]} = Store.read(e.paths.todo)
    assert t.raw == "new text +p"
  end

  test "pri rejects invalid priority and done tasks", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "x done\nopen\n")
    assert {:error, _} = CLI.run(["pri", "2", "1"], e)
    assert {:error, _} = CLI.run(["pri", "1", "A"], e)
  end

  test "mv moves task to done.txt", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "one\ntwo\n")
    {:ok, _} = CLI.run(["mv", "1", "done"], e)
    assert {:ok, [t]} = Store.read(e.paths.todo)
    assert t.raw == "two"
    assert {:ok, [d]} = Store.read(e.paths.done)
    assert d.raw == "one"
  end

  test "mv moves task back to todo.txt", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "open\n")
    File.write!(e.paths.done, "x 2026-09-20 old\n")
    {:ok, _} = CLI.run(["move", "1", "todo"], e)
    assert {:ok, []} = Store.read(e.paths.done)
    assert {:ok, [_, t]} = Store.read(e.paths.todo)
    assert t.raw == "x 2026-09-20 old"
  end

  test "mv rejects a bad destination", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "one\n")
    assert {:usage, _} = CLI.run(["mv", "1", "elsewhere"], e)
  end

  test "listall includes done file; listproj/listcon/listpri", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "a +p1 @c1\nb +p2\n")
    File.write!(e.paths.done, "x 2026-09-20 old +p1\n")
    {:ok, out} = CLI.run(["--plain", "listall"], e)
    assert out =~ "a +p1" and out =~ "old +p1"
    {:ok, out} = CLI.run(["--plain", "listproj"], e)
    assert out =~ "+p1" and out =~ "+p2"
    {:ok, out} = CLI.run(["--plain", "listcon"], e)
    assert out =~ "@c1"
    {:ok, _} = CLI.run(["pri", "1", "A"], e)
    {:ok, out} = CLI.run(["--plain", "listpri", "A"], e)
    assert out =~ "a +p1"
  end

  test "due buckets", %{env: e, dir: dir} do
    File.mkdir_p!(dir)

    File.write!(
      e.paths.todo,
      "old due:2026-09-19\nnow due:2026-09-21\nsoon due:2026-09-25\nfar due:2026-10-15\nx done due:2026-09-19\n"
    )

    {:ok, out} = CLI.run(["--plain", "due"], e)
    [overdue | _] = String.split(out, "\n\n")
    assert overdue =~ "old" and overdue =~ "OVERDUE"
    assert out =~ "TODAY" and out =~ "THIS WEEK" and out =~ "LATER"
    # done tasks excluded
    refute out =~ "x done"
  end

  test "agenda lists next 14 days by date", %{env: e, dir: dir} do
    File.mkdir_p!(dir)

    File.write!(
      e.paths.todo,
      "a due:2026-09-22\nb due:2026-09-22\nc t:2026-09-25 due:2026-09-26\n"
    )

    {:ok, out} = CLI.run(["--plain", "agenda"], e)
    assert out =~ "2026-09-22" and out =~ "a due" and out =~ "b due"
  end

  test "agenda surfaces upcoming t: thresholds", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "hidden soon t:2026-09-25\nfar t:2027-01-01\n")
    {:ok, out} = CLI.run(["--plain", "agenda"], e)
    assert out =~ "THRESHOLDS" and out =~ "hidden soon"
    refute out =~ "far"
  end
end
