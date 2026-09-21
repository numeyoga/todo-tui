defmodule TodoTxt.ConfigTest do
  use ExUnit.Case, async: false
  alias TodoTxt.Config

  @env_vars [
    "XDG_DATA_HOME",
    "XDG_CONFIG_HOME",
    "TODOTXT_DIR",
    "TODOTXT_TODO_FILE",
    "TODOTXT_DONE_FILE"
  ]

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ttcfg#{System.system_time(:nanosecond)}#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    saved = Map.new(@env_vars, fn k -> {k, System.get_env(k)} end)
    Enum.each(@env_vars, &System.delete_env/1)

    # isolate from any real user config file
    System.put_env("XDG_CONFIG_HOME", Path.join(dir, "cfg"))

    on_exit(fn ->
      Enum.each(saved, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)

      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  test "resolve_paths defaults to XDG_DATA_HOME/todo", %{dir: d} do
    System.put_env("XDG_DATA_HOME", d)

    paths = Config.resolve_paths(%{})
    assert paths.todo == Path.join(d, "todo/todo.txt")
    assert paths.done == Path.join(d, "todo/done.txt")
    assert paths.report == Path.join(d, "todo/report.txt")
  end

  test "file: flag wins over TODOTXT_TODO_FILE env", %{dir: d} do
    System.put_env("XDG_DATA_HOME", d)
    System.put_env("TODOTXT_TODO_FILE", Path.join(d, "env.txt"))

    paths = Config.resolve_paths(%{file: Path.join(d, "flag.txt")})
    assert paths.todo == Path.join(d, "flag.txt")
  end

  test "TODOTXT_TODO_FILE env wins over default", %{dir: d} do
    System.put_env("XDG_DATA_HOME", d)
    System.put_env("TODOTXT_TODO_FILE", Path.join(d, "env.txt"))

    paths = Config.resolve_paths(%{})
    assert paths.todo == Path.join(d, "env.txt")
  end

  test "done_file: flag wins over TODOTXT_DONE_FILE env", %{dir: d} do
    System.put_env("XDG_DATA_HOME", d)
    System.put_env("TODOTXT_DONE_FILE", Path.join(d, "env_done.txt"))

    paths = Config.resolve_paths(%{done_file: Path.join(d, "flag_done.txt")})
    assert paths.done == Path.join(d, "flag_done.txt")
  end

  test "TODOTXT_DIR overrides the todo dir", %{dir: d} do
    System.put_env("TODOTXT_DIR", Path.join(d, "custom"))

    paths = Config.resolve_paths(%{})
    assert paths.todo == Path.join(d, "custom/todo.txt")
    assert paths.done == Path.join(d, "custom/done.txt")
    assert paths.report == Path.join(d, "custom/report.txt")
  end

  test "TODO_DIR in config file is honored", %{dir: d} do
    cfg = Path.join(d, "cfg")
    File.mkdir_p!(Path.join(cfg, "todotxt"))
    File.write!(Path.join([cfg, "todotxt", "config"]), "TODO_DIR=#{d}/fromcfg\n")
    System.put_env("XDG_DATA_HOME", Path.join(d, "data"))

    paths = Config.resolve_paths(%{})
    assert paths.todo == Path.join(d, "fromcfg/todo.txt")
  end

  test "load_file parses KEY=value lines, missing file returns %{}", %{dir: d} do
    assert Config.load_file() == %{}

    cfg = Path.join(d, "cfg")
    File.mkdir_p!(Path.join(cfg, "todotxt"))

    File.write!(Path.join([cfg, "todotxt", "config"]), "TODO_DIR=/a/b\nEMPTY=\nnovalue\n")

    assert Config.load_file() == %{"TODO_DIR" => "/a/b", "EMPTY" => ""}
  end
end
