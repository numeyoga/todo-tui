defmodule TodoTxt.CLITest do
  use ExUnit.Case

  alias TodoTxt.{CLI, Store}

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ttcli#{System.system_time(:nanosecond)}#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    env = %{
      paths: %{
        todo: Path.join(dir, "todo.txt"),
        done: Path.join(dir, "done.txt"),
        report: Path.join(dir, "report.txt")
      },
      today: ~D[2026-09-21],
      # isolate from any real config file; config tests override/delete this
      config: %{}
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

  test "add keeps a leading (A) priority ahead of the creation date", %{env: e} do
    assert {:ok, out} = TodoTxt.CLI.run(["add", "(A) urgent @phone"], e)
    assert out =~ "(A)"
    {:ok, [t]} = TodoTxt.Store.read(e.paths.todo)
    assert t.priority == ?A
    assert t.creation_date == ~D[2026-09-21]
    assert t.description =~ "urgent"
    refute t.description =~ "(A)"
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
    assert d.raw == "x 2026-09-21 one" and d.done
  end

  test "mv done completes a prioritized task (priority → pri:)", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "(A) one\n")
    {:ok, _} = CLI.run(["mv", "1", "done"], e)
    assert {:ok, [d]} = Store.read(e.paths.done)
    assert d.raw == "x 2026-09-21 one pri:A"
  end

  test "mv moves task back to todo.txt", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "open\n")
    File.write!(e.paths.done, "x 2026-09-20 old\n")
    {:ok, _} = CLI.run(["move", "1", "todo"], e)
    assert {:ok, []} = Store.read(e.paths.done)
    assert {:ok, [_, t]} = Store.read(e.paths.todo)
    assert t.raw == "old" and not t.done
  end

  test "mv todo reopens and restores a pri: priority", %{env: e, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(e.paths.todo, "")
    File.write!(e.paths.done, "x 2026-09-20 old pri:C\n")
    {:ok, _} = CLI.run(["mv", "1", "todo"], e)
    assert {:ok, [t]} = Store.read(e.paths.todo)
    assert t.raw == "(C) old"
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

  test "listpri --json emits the task objects", %{env: e} do
    File.write!(e.paths.todo, "(A) a +p1\nb\n(A) c\n")
    {:ok, out} = CLI.run(["--json", "listpri", "A"], e)
    decoded = Jason.decode!(out)
    assert Enum.map(decoded, & &1["description"]) == ["a +p1", "c"]
    assert Enum.all?(decoded, &(&1["priority"] == "A"))
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

  test "archive moves x tasks to done.txt and creates it", %{env: e} do
    File.write!(e.paths.todo, "x done1\nopen\nx done2\n")
    {:ok, _} = CLI.run(["archive"], e)
    assert {:ok, [t]} = Store.read(e.paths.todo)
    assert t.raw == "open"
    {:ok, ds} = Store.read(e.paths.done)
    assert length(ds) == 2
  end

  test "dedupe removes duplicate lines keeping first", %{env: e} do
    File.write!(e.paths.todo, "same\nother\nsame\n")
    {:ok, _} = CLI.run(["dedupe"], e)
    {:ok, ts} = Store.read(e.paths.todo)
    assert Enum.map(ts, & &1.raw) == ["same", "other"]
  end

  test "report appends dated stats", %{env: e} do
    File.write!(e.paths.todo, "a\nb\n")
    File.write!(e.paths.done, "x c\n")
    {:ok, _} = CLI.run(["report"], e)
    assert File.read!(e.paths.report) =~ "2026-09-21 2 1"
  end

  test "help and --version", %{env: e} do
    assert {:ok, out} = CLI.run(["help"], e)
    assert out =~ "add" and out =~ "ls" and out =~ "do"
    assert {:ok, out} = CLI.run(["--version"], e)
    assert out =~ "todo 0.1.0"
  end

  test "edit runs $EDITOR and reports exit status", %{env: e} do
    old_editor = System.get_env("EDITOR")
    old_visual = System.get_env("VISUAL")

    on_exit(fn ->
      if old_editor, do: System.put_env("EDITOR", old_editor), else: System.delete_env("EDITOR")
      if old_visual, do: System.put_env("VISUAL", old_visual), else: System.delete_env("VISUAL")
    end)

    # VISUAL a la priorité sur EDITOR — le neutraliser pour isoler le test.
    System.delete_env("VISUAL")
    System.put_env("EDITOR", "true")
    assert {:ok, out} = CLI.run(["edit"], e)
    assert out =~ "edited"

    System.put_env("EDITOR", "false")
    assert {:error, m} = CLI.run(["edit"], e)
    assert m =~ "exited"
  end

  test "listaddons reports no addon support", %{env: e} do
    assert {:ok, "(no addons support)"} = CLI.run(["listaddons"], e)
  end

  test "ls --json emits decodable task list", %{env: e} do
    File.write!(e.paths.todo, "(A) call mom +fam @p due:2026-09-25\n")
    {:ok, json} = CLI.run(["--json", "ls"], e)

    assert [%{"line" => 1, "priority" => "A", "tags" => %{"due" => "2026-09-25"}}] =
             Jason.decode!(json)
  end

  test "listall/due --json also emit JSON", %{env: e} do
    File.write!(e.paths.todo, "a due:2026-09-19\n")
    assert {:ok, j} = CLI.run(["--json", "due"], e)
    assert [_ | _] = Jason.decode!(j)
  end

  test "listall --json includes tasks from both files", %{env: e} do
    File.write!(e.paths.todo, "open +p\n")
    File.write!(e.paths.done, "x 2026-09-20 old +p\n")
    assert {:ok, j} = CLI.run(["--json", "listall"], e)
    decoded = Jason.decode!(j)
    assert length(decoded) == 2
    assert Enum.any?(decoded, &(&1["done"] == true))
  end

  test "due --json adds a bucket field to each task", %{env: e} do
    File.write!(e.paths.todo, "old due:2026-09-19\nnow due:2026-09-21\nnone\n")
    assert {:ok, j} = CLI.run(["--json", "due"], e)
    decoded = Jason.decode!(j)
    assert Enum.find(decoded, &(&1["line"] == 1))["bucket"] == "overdue"
    assert Enum.find(decoded, &(&1["line"] == 2))["bucket"] == "today"
    # tasks without a valid due: tag are excluded, like the text output
    refute Enum.any?(decoded, &(&1["line"] == 3))
  end

  test "listproj/listcon --json emit JSON arrays", %{env: e} do
    File.write!(e.paths.todo, "a +p1 @c1\nb +p2\n")
    assert {:ok, j} = CLI.run(["--json", "listproj"], e)
    assert Jason.decode!(j) == ["+p1", "+p2"]
    assert {:ok, j} = CLI.run(["--json", "listcon"], e)
    assert Jason.decode!(j) == ["@c1"]
  end

  test "agenda --json emits dates map and thresholds list", %{env: e} do
    File.write!(e.paths.todo, "a due:2026-09-22\nb due:2026-09-22\nsoon t:2026-09-25\n")

    assert {:ok, j} = CLI.run(["--json", "agenda"], e)
    decoded = Jason.decode!(j)
    assert %{"dates" => dates, "thresholds" => thresholds} = decoded
    assert [%{"line" => 1}, %{"line" => 2}] = dates["2026-09-22"]
    assert [%{"line" => 3}] = thresholds
  end

  test "add repairs a missing trailing newline instead of corrupting", %{env: e} do
    File.write!(e.paths.todo, "task one")
    assert {:ok, out} = CLI.run(["add", "task two"], e)
    assert out =~ "2:"
    assert File.read!(e.paths.todo) == "task one\n2026-09-21 task two\n"
  end

  test "add on a file with trailing blank lines echoes and lands on the next real line",
       %{env: e} do
    File.write!(e.paths.todo, "a\n\n\n")
    assert {:ok, out} = CLI.run(["add", "b"], e)
    assert out =~ "2:"
    assert File.read!(e.paths.todo) == "a\n2026-09-21 b\n"
    {:ok, tasks} = Store.read(e.paths.todo)
    assert List.last(tasks).line == 2
  end

  test "global flags work after the command", %{env: e} do
    File.write!(e.paths.todo, "(A) call mom +fam\n")
    assert {:ok, j} = CLI.run(["ls", "--json"], e)
    assert [%{"line" => 1, "priority" => "A"}] = Jason.decode!(j)
    # --plain also works in any position
    assert {:ok, out} = CLI.run(["ls", "--plain"], e)
    assert out == "1: (A) call mom +fam"
  end

  test "-f after the command selects the todo file", %{env: e} do
    other = Path.join(dir_of(e), "other.txt")
    File.write!(other, "x\n")

    # drop injected paths so -f drives resolve_paths; keep done.txt in tmp
    old = System.get_env("TODOTXT_DONE_FILE")
    on_exit(fn -> restore_env("TODOTXT_DONE_FILE", old) end)
    System.put_env("TODOTXT_DONE_FILE", Path.join(dir_of(e), "done.txt"))

    env = Map.delete(e, :paths)
    assert {:ok, out} = CLI.run(["ls", "--plain", "-f", other], env)
    assert out == "1: x"
  end

  test "unknown options and dangling -f are usage errors", %{env: e} do
    assert {:usage, m} = CLI.run(["ls", "--bogus"], e)
    assert m =~ "--bogus"
    assert {:usage, m} = CLI.run(["--bogus"], e)
    assert m =~ "--bogus"
    assert {:usage, m} = CLI.run(["-f"], e)
    assert m =~ "-f"
    # a positional that is not a command stays a usage error
    assert {:usage, m} = CLI.run(["bogus-flag"], e)
    assert m =~ "bogus-flag"
  end

  test "--file=X form works", %{env: e, dir: dir} do
    other = Path.join(dir, "other.txt")
    File.write!(other, "z\n")

    old = System.get_env("TODOTXT_DONE_FILE")
    on_exit(fn -> restore_env("TODOTXT_DONE_FILE", old) end)
    System.put_env("TODOTXT_DONE_FILE", Path.join(dir, "done.txt"))

    env = Map.delete(e, :paths)
    assert {:ok, out} = CLI.run(["--file=#{other}", "ls", "--plain"], env)
    assert out == "1: z"
  end

  test "mv appends to destination first: append failure keeps the source intact",
       %{env: e} do
    File.write!(e.paths.todo, "one\ntwo\n")
    # done.txt.tmp as a directory makes the atomic append to done.txt fail
    File.write!(e.paths.done, "")
    File.mkdir_p!(e.paths.done <> ".tmp")
    assert {:error, _} = CLI.run(["mv", "1", "done"], e)
    {:ok, tasks} = Store.read(e.paths.todo)
    assert Enum.map(tasks, & &1.raw) == ["one", "two"]
  end

  test "do with a malformed recur: tag errors and leaves the file unchanged",
       %{env: e} do
    File.write!(e.paths.todo, "task recur:banana\n")
    assert {:error, m} = CLI.run(["do", "1"], e)
    assert m =~ "banana" and m =~ "1"
    assert File.read!(e.paths.todo) == "task recur:banana\n"
  end

  test "do recur +1w shifts t: along with due:, preserving the offset", %{env: e} do
    # today = 2026-09-21 → due: 2026-09-28 ; t: garde l'écart d'1 jour → 2026-09-27
    File.write!(e.paths.todo, "renew t:2026-09-24 due:2026-09-25 recur:+1w\n")
    assert {:ok, out} = CLI.run(["do", "1"], e)
    assert out =~ "t:2026-09-27" and out =~ "due:2026-09-28"
    {:ok, [_, new]} = Store.read(e.paths.todo)
    assert new.tags["t"] == "2026-09-27" and new.tags["due"] == "2026-09-28"
  end

  test "do recur +1w with t: but no due: shifts t: from today", %{env: e} do
    File.write!(e.paths.todo, "renew t:2026-09-24 recur:+1w\n")
    assert {:ok, _} = CLI.run(["do", "1"], e)
    {:ok, [_, new]} = Store.read(e.paths.todo)
    assert new.tags["t"] == "2026-09-28" and new.tags["due"] == "2026-09-28"
  end

  test "do moves the priority into pri: and undo restores it", %{env: e} do
    File.write!(e.paths.todo, "(A) tâche\n")
    assert {:ok, "1: x 2026-09-21 tâche pri:A"} = CLI.run(["do", "1"], e)
    assert {:ok, [t]} = Store.read(e.paths.todo)
    assert t.raw == "x 2026-09-21 tâche pri:A" and t.priority == nil
    assert {:ok, "1: (A) tâche"} = CLI.run(["undo", "1"], e)
    assert {:ok, [t]} = Store.read(e.paths.todo)
    assert t.raw == "(A) tâche" and t.priority == ?A and t.tags["pri"] == nil
  end

  test "do on a prioritized recurring task keeps the priority on the next occurrence",
       %{env: e} do
    File.write!(e.paths.todo, "(B) renew due:2026-09-25 recur:+1w\n")
    assert {:ok, _} = CLI.run(["do", "1"], e)
    assert {:ok, [done, new]} = Store.read(e.paths.todo)
    assert done.raw == "x 2026-09-21 renew due:2026-09-25 recur:+1w pri:B"
    assert new.raw == "(B) 2026-09-21 renew due:2026-09-28 recur:+1w"
  end

  test "do recur strict 1w preserves the t:↔due: offset", %{env: e} do
    File.write!(e.paths.todo, "renew t:2026-09-24 due:2026-09-25 recur:1w\n")
    assert {:ok, _} = CLI.run(["do", "1"], e)
    {:ok, [_, new]} = Store.read(e.paths.todo)
    assert new.tags["t"] == "2026-10-01" and new.tags["due"] == "2026-10-02"
  end

  test "help and listaddons do not read the task files", %{env: e} do
    # a directory at the todo path makes Store.read fail
    File.mkdir_p!(e.paths.todo)
    File.mkdir_p!(e.paths.done)
    assert {:ok, out} = CLI.run(["help"], e)
    assert out =~ "add"
    assert {:ok, "(no addons support)"} = CLI.run(["listaddons"], e)
    assert {:ok, out} = CLI.run(["-h"], e)
    assert out =~ "add"
    # sanity: a real command does hit the files and fails
    assert {:error, _} = CLI.run(["ls"], e)
  end

  test "--tui dispatches to Tui.run and returns its result" do
    test_pid = self()

    env = %{
      paths: %{todo: "t.txt", done: "d.txt", report: "r.txt"},
      tasks: [],
      done_tasks: [],
      today: ~D[2026-09-21],
      runner: fn env -> send(test_pid, {:tui_ran, env.paths.todo}) && {:ok, nil} end
    }

    assert {:ok, nil} = TodoTxt.CLI.run(["--tui"], env)
    assert_received {:tui_ran, "t.txt"}
  end

  test "--tui rejects extra args" do
    assert {:usage, _} = TodoTxt.CLI.run(["--tui", "ls"], %{today: ~D[2026-09-21]})
  end

  test "--tui with unreadable file returns error before starting runtime" do
    # A directory path -> File.read returns {:error, :eisdir}.
    # (enoent reads as {:ok, []} by Store design — use a real error case.)
    dir =
      Path.join(System.tmp_dir!(), "todotxt-tui-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    env = %{
      paths: %{todo: dir, done: "d", report: "r"},
      today: ~D[2026-09-21],
      runner: fn _ -> raise "must not run" end
    }

    assert {:error, msg} = TodoTxt.CLI.run(["--tui"], env)
    assert msg =~ "cannot read"
  end

  test "COLORS=off in config file forces plain output", %{env: e, dir: dir} do
    env = with_config_file(dir, "COLORS=off\n", e)
    File.write!(e.paths.todo, "(A) a\n")

    old_term = System.get_env("TERM")
    old_nc = System.get_env("NO_COLOR")

    on_exit(fn ->
      restore_env("TERM", old_term)
      restore_env("NO_COLOR", old_nc)
    end)

    System.put_env("TERM", "xterm-256color")
    System.delete_env("NO_COLOR")

    assert {:ok, out} = CLI.run(["ls"], env)
    refute out =~ "\e["
    assert out == "1: (A) a"
  end

  test "LS_SORT=line in config file sorts ls by line only", %{env: e, dir: dir} do
    env = with_config_file(dir, "LS_SORT=line\n", e)
    File.write!(e.paths.todo, "plain\n(B) b\n")

    assert {:ok, out} = CLI.run(["--plain", "ls"], env)
    assert out == "1: plain\n2: (B) b"
    # listall too
    assert {:ok, out} = CLI.run(["--plain", "listall"], env)
    assert out == "1: plain\n2: (B) b"
  end

  defp dir_of(env), do: Path.dirname(env.paths.todo)

  defp restore_env(k, nil), do: System.delete_env(k)
  defp restore_env(k, v), do: System.put_env(k, v)

  # Point XDG_CONFIG_HOME at a tmp dir holding the given config body and
  # drop the injected :config so CLI.run loads the real file.
  defp with_config_file(dir, body, env) do
    cfg = Path.join(dir, "cfg")
    File.mkdir_p!(Path.join(cfg, "todotxt"))
    File.write!(Path.join([cfg, "todotxt", "config"]), body)

    old = System.get_env("XDG_CONFIG_HOME")
    System.put_env("XDG_CONFIG_HOME", cfg)
    on_exit(fn -> restore_env("XDG_CONFIG_HOME", old) end)

    Map.delete(env, :config)
  end
end
