defmodule TodoTxt.CLITest do
  use ExUnit.Case

  setup do
    dir = Path.join(System.tmp_dir!(), "tt#{System.unique_integer([:positive])}")

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

  test "unknown command is a usage error", %{env: e} do
    assert {:usage, m} = TodoTxt.CLI.run(["bogus"], e)
    assert m =~ "bogus"
  end
end
