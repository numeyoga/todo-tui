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
