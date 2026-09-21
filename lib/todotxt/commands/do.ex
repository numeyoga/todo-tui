defmodule TodoTxt.Commands.Do do
  @moduledoc """
  `todo do ITEM#` — mark a task as done.

  Sets `done` and `completion_date` to today, drops the priority.
  If the task recurs (`recur:` tag), the next occurrence is appended
  and echoed after the completed task.
  """

  alias TodoTxt.{Commands.Helpers, Ops, Parser, Store, Task}

  def run([n | _], %{tasks: tasks, paths: paths, today: today}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, tasks2, recur} <- Ops.complete(tasks, t, today),
         :ok <- Store.write(paths.todo, tasks2),
         {:ok, note} <- append_recurrence(recur, tasks, paths) do
      done = Task.complete(t, today)
      {:ok, "#{t.line}: #{Parser.render(done)}#{note}"}
    end
  end

  def run(_, _), do: {:usage, "todo do ITEM#"}

  defp append_recurrence(nil, _tasks, _paths), do: {:ok, ""}

  defp append_recurrence(new, tasks, paths) do
    # Interior blank lines make `length(tasks)` smaller than the
    # real last line number — number past the max existing line.
    new = %{new | line: Ops.next_line(tasks)}

    case Store.append(paths.todo, [new]) do
      :ok -> {:ok, "\n#{new.line}: #{Parser.render(new)}"}
      {:error, m} -> {:error, m}
    end
  end
end
