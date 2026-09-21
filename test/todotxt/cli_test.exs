defmodule TodoTxt.CLITest do
  use ExUnit.Case

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
end
