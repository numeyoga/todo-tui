defmodule TodoTxt.Commands.ListAll do
  @moduledoc """
  `todo listall` — list every task from both `todo.txt` and
  `done.txt`, sorted by priority then line number.
  """

  alias TodoTxt.{Format, Query}

  def run(_, %{tasks: tasks, done_tasks: done_tasks, opts: opts}) do
    shown = sort(tasks ++ done_tasks, opts)
    {:ok, Format.render(shown, opts)}
  end

  # `LS_SORT=line` (config file) sorts by line only, ignoring priority.
  defp sort(tasks, opts) do
    if Map.get(opts, :sort) == "line",
      do: Enum.sort_by(tasks, & &1.line),
      else: Query.sort(tasks)
  end
end
