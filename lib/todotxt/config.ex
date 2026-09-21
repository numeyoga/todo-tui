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
      {:ok, c} ->
        Enum.reduce(String.split(c, "\n"), %{}, fn line, acc ->
          case String.split(line, "=", parts: 2) do
            [k, v] ->
              k = String.trim(k)
              if k == "", do: acc, else: Map.put(acc, k, String.trim(v))

            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end
end
