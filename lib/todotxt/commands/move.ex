defmodule TodoTxt.Commands.Move do
  @moduledoc """
  `todo mv ITEM# done|todo` — move a task between `todo.txt` and
  `done.txt`. Numbers are line numbers in the *source* file; the task
  is appended at the end of the destination file.
  """

  alias TodoTxt.{Commands.Helpers, Store}

  def run([n, "done"], %{tasks: tasks, paths: paths}) do
    move(tasks, n, paths.todo, paths.done, "done")
  end

  def run([n, "todo"], %{done_tasks: done_tasks, paths: paths}) do
    move(done_tasks, n, paths.done, paths.todo, "todo")
  end

  def run(_, _), do: {:usage, "todo mv ITEM# done|todo"}

  defp move(tasks, n, src, dest, name) do
    # Append to the destination first: if it fails the task is still
    # in the source — a duplicate beats a loss (same order as archive).
    with {:ok, t} <- Helpers.fetch(tasks, n),
         :ok <- Store.append(dest, [t]),
         :ok <- Store.write(src, Enum.reject(tasks, &(&1.line == t.line))) do
      {:ok, "#{t.line}: moved to #{name}"}
    end
  end
end
