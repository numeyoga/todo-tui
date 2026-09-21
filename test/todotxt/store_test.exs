defmodule TodoTxt.StoreTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Parser, Store}

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "tt#{System.system_time(:nanosecond)}#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "read missing file returns empty list", %{dir: d} do
    assert Store.read(Path.join(d, "todo.txt")) == {:ok, []}
  end

  test "write then read round-trips tasks", %{dir: d} do
    p = Path.join(d, "todo.txt")
    tasks = Parser.parse_all("(A) one\ntwo")
    assert :ok = Store.write(p, tasks)
    assert {:ok, [t1, t2]} = Store.read(p)
    assert t1.priority == ?A and t2.line == 2
  end

  test "append creates file and preserves content", %{dir: d} do
    p = Path.join(d, "done.txt")
    :ok = Store.append(p, Parser.parse_all("x done1"))
    :ok = Store.append(p, Parser.parse_all("x done2"))
    {:ok, ts} = Store.read(p)
    assert length(ts) == 2
  end

  test "append repairs a missing trailing newline", %{dir: d} do
    p = Path.join(d, "todo.txt")
    File.write!(p, "task one")
    assert :ok = Store.append(p, Parser.parse_all("task two"))
    assert File.read!(p) == "task one\ntask two\n"
    assert {:ok, [t1, t2]} = Store.read(p)
    assert t1.line == 1 and t2.line == 2
  end

  test "append compacts trailing blank lines so the task lands at max line + 1",
       %{dir: d} do
    p = Path.join(d, "todo.txt")
    File.write!(p, "a\n\n\n")
    assert :ok = Store.append(p, Parser.parse_all("b"))
    assert File.read!(p) == "a\nb\n"
    assert {:ok, [_, t2]} = Store.read(p)
    assert t2.line == 2
  end

  test "append_line repairs a missing trailing newline", %{dir: d} do
    p = Path.join(d, "report.txt")
    File.write!(p, "2026-09-20 1 0")
    assert :ok = Store.append_line(p, "2026-09-21 2 1")
    assert File.read!(p) == "2026-09-20 1 0\n2026-09-21 2 1\n"
  end

  test "append_line compacts trailing blank lines", %{dir: d} do
    p = Path.join(d, "report.txt")
    File.write!(p, "2026-09-20 1 0\n\n")
    assert :ok = Store.append_line(p, "2026-09-21 2 1")
    assert File.read!(p) == "2026-09-20 1 0\n2026-09-21 2 1\n"
  end

  test "append to a directory returns error tuple", %{dir: d} do
    p = Path.join(d, "adir")
    File.mkdir_p!(p)
    assert {:error, msg} = Store.append(p, Parser.parse_all("x done1"))
    assert msg =~ "cannot append"
  end

  test "append_line appends a raw line and creates the file", %{dir: d} do
    p = Path.join([d, "sub", "report.txt"])
    assert :ok = Store.append_line(p, "2026-09-21 2 1")
    assert :ok = Store.append_line(p, "2026-09-22 3 1")
    assert File.read!(p) == "2026-09-21 2 1\n2026-09-22 3 1\n"
  end

  test "append_line to a directory returns error tuple", %{dir: d} do
    p = Path.join(d, "adir")
    File.mkdir_p!(p)
    assert {:error, msg} = Store.append_line(p, "x")
    assert msg =~ "cannot append"
  end

  test "write_atomic leaves no tmp file and creates parent dirs", %{dir: d} do
    p = Path.join([d, "sub", "dir", "todo.txt"])
    assert :ok = Store.write_atomic(p, "hello\n")
    assert File.read!(p) == "hello\n"
    refute File.exists?(p <> ".tmp")
  end

  test "write creates parent directories", %{dir: d} do
    p = Path.join([d, "deep", "todo.txt"])
    assert :ok = Store.write(p, Parser.parse_all("task"))
    assert {:ok, [_]} = Store.read(p)
  end

  test "write of empty list writes empty file", %{dir: d} do
    p = Path.join(d, "todo.txt")
    assert :ok = Store.write(p, [])
    assert File.read!(p) == ""
  end

  test "read error other than enoent returns error tuple", %{dir: d} do
    p = Path.join(d, "adir")
    File.mkdir_p!(p)
    assert {:error, msg} = Store.read(p)
    assert msg =~ "cannot read"
  end
end
