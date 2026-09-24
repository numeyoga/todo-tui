defmodule TodoTxt.Commands.Do do
  @moduledoc """
  `todo do ITEM#` — mark a task as done.

  Sets `done` and `completion_date` to today; a priority is moved into
  a `pri:X` tag (todo.txt convention) so `undo` can restore it.
  If the task recurs (`recur:` tag), the next occurrence is appended
  and echoed after the completed task.
  """

  alias TodoTxt.{Commands.Helpers, Parser, Tasks}

  def run([n | _], %{tasks: tasks, paths: paths, today: today}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, %{task: done, recur: recur}} <- Tasks.complete(paths, tasks, t, today) do
      {:ok, "#{t.line}: #{Parser.render(done)}#{recur_note(recur)}"}
    end
  end

  def run(_, _), do: {:usage, "todo do ITEM#"}

  defp recur_note(nil), do: ""
  defp recur_note(new), do: "\n#{new.line}: #{Parser.render(new)}"
end
