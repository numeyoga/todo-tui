defmodule TodoTxt.Config do
  @moduledoc """
  Path resolution for todo.txt files.

  Precedence: CLI flags > env vars > config file (`TODO_DIR`) > XDG defaults.
  Config file lives at `$XDG_CONFIG_HOME/todotxt/config` (`KEY=value` lines).
  """

  @spec resolve_paths(map) :: %{todo: Path.t(), done: Path.t(), report: Path.t()}
  def resolve_paths(opts \\ %{}) do
    data = System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share")
    dir = System.get_env("TODOTXT_DIR") || load_file()["TODO_DIR"] || Path.join(data, "todo")

    %{
      todo: opts[:file] || System.get_env("TODOTXT_TODO_FILE") || Path.join(dir, "todo.txt"),
      done: opts[:done_file] || System.get_env("TODOTXT_DONE_FILE") || Path.join(dir, "done.txt"),
      report: Path.join(dir, "report.txt")
    }
  end

  @spec load_file() :: %{String.t() => String.t()}
  def load_file do
    cfg = System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")
    path = Path.join(cfg, "todotxt/config")

    case File.read(path) do
      {:ok, c} -> c |> String.split("\n") |> Enum.reduce(%{}, &put_line/2)
      _ -> %{}
    end
  end

  defp put_line(line, acc) do
    with [k, v] <- String.split(line, "=", parts: 2),
         k when k != "" <- String.trim(k) do
      Map.put(acc, k, String.trim(v))
    else
      _ -> acc
    end
  end
end
