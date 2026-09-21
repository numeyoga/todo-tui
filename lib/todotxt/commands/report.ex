defmodule TodoTxt.Commands.Report do
  @moduledoc """
  `todo report` — append dated stats to report.txt.

  Each run appends one line `YYYY-MM-DD <open> <done>` where
  `open` is the number of open tasks in todo.txt and `done` is the
  number of tasks in done.txt plus done tasks still in todo.txt.
  """

  alias TodoTxt.Store

  def run(_args, %{tasks: tasks, done_tasks: done_tasks, paths: paths, today: today}) do
    open = Enum.count(tasks, &(not &1.done))
    done = length(done_tasks) + Enum.count(tasks, & &1.done)

    with :ok <- Store.append_line(paths.report, "#{today} #{open} #{done}") do
      {:ok, "#{today} #{open} #{done}"}
    end
  end
end
