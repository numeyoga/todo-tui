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

  @doc """
  Renders a task list as JSON when `opts.json` is set, otherwise
  as `"N: <raw line>"` text lines (see `tasks/2`).
  """
  def render(tasks, %{json: true}), do: tasks_json(tasks)
  def render(tasks, opts), do: tasks(tasks, opts)

  @doc "Pretty-printed JSON array of `task_map/1` maps."
  def tasks_json(tasks), do: Jason.encode!(Enum.map(tasks, &task_map/1), pretty: true)

  @doc """
  Whether ANSI colors are wanted: off when `opts[:plain]`, `NO_COLOR`
  is set, or `TERM` is unset/`dumb`. Shared with the TUI palette.
  """
  def colors_enabled?(opts) do
    !opts[:plain] and is_nil(System.get_env("NO_COLOR")) and
      System.get_env("TERM") not in [nil, "dumb"]
  end

  def tasks(tasks, opts) do
    color = colors_enabled?(opts)

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
