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
end
