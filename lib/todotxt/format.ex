defmodule TodoTxt.Format do
  @moduledoc """
  Renders tasks as `"N: <raw line>"` strings, optionally with ANSI
  colors, and exposes `task_map/1` for JSON output.

  Returns strings — never prints. Colors are emitted unless
  `opts.plain`, `NO_COLOR` is set, or `TERM` is unset/`dumb`.
  """

  @colors %{
    ?A => IO.ANSI.red() <> IO.ANSI.bright(),
    ?B => IO.ANSI.yellow(),
    ?C => IO.ANSI.cyan()
  }

  def tasks(tasks, opts) do
    color =
      not opts.plain and is_nil(System.get_env("NO_COLOR")) and
        System.get_env("TERM") not in [nil, "dumb"]

    Enum.map_join(tasks, "\n", fn t ->
      line = "#{t.line}: #{t.raw}"
      if color, do: colorize(t, line), else: line
    end)
  end

  defp colorize(%{done: true}, line), do: IO.ANSI.faint() <> line <> IO.ANSI.reset()

  defp colorize(%{priority: p}, line) when p in [?A, ?B, ?C],
    do: @colors[p] <> line <> IO.ANSI.reset()

  defp colorize(_, line), do: line

  @doc "Map view of a task, for JSON output (`--json`)."
  def task_map(t) do
    %{
      line: t.line,
      done: t.done,
      priority: if(t.priority, do: <<t.priority>>),
      completion_date: t.completion_date && Date.to_string(t.completion_date),
      creation_date: t.creation_date && Date.to_string(t.creation_date),
      description: t.description,
      projects: t.projects,
      contexts: t.contexts,
      tags: t.tags
    }
  end
end
