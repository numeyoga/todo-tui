defmodule TodoTxt.Commands.Move do
  @moduledoc """
  `todo mv ITEM# done|todo` — move a task between `todo.txt` and
  `done.txt`. Numbers are line numbers in the *source* file; the task
  is appended at the end of the destination file.

  Moving to `done` completes the task (`x <today>`, priority moved to
  `pri:X`); moving to `todo` reopens it (`x`/completion date removed,
  `pri:X` restored as priority).
  """

  alias TodoTxt.{Commands.Helpers, Task, Tasks}

  def run([n, "done"], %{tasks: tasks, paths: paths, today: today}) do
    move(tasks, n, paths.todo, paths.done, "done", &Task.complete(&1, today))
  end

  def run([n, "todo"], %{done_tasks: done_tasks, paths: paths}) do
    move(done_tasks, n, paths.done, paths.todo, "todo", &Task.uncomplete/1)
  end

  def run(_, _), do: {:usage, "todo mv ITEM# done|todo"}

  defp move(tasks, n, src, dest, name, transform) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, _} <- Tasks.move(src, dest, tasks, transform.(t)) do
      {:ok, "#{t.line}: moved to #{name}"}
    end
  end
end
