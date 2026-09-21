defmodule TodoTxt.Commands.Do do
  @moduledoc """
  `todo do ITEM#` — mark a task as done.

  Sets `done` and `completion_date` to today, drops the priority.
  If the task recurs (`recur:` tag), the next occurrence is appended
  and echoed after the completed task.
  """

  alias TodoTxt.{Commands.Helpers, Parser, Store, Task}

  def run([n | _], %{tasks: tasks, paths: paths, today: today}) do
    done = fn t -> Task.complete(t, today) end

    with {:ok, t} <- Helpers.fetch(tasks, n),
         :ok <- Store.write(paths.todo, Helpers.replace(tasks, done.(t))),
         {:ok, recur_note} <- append_recurrence(t, tasks, paths, today) do
      {:ok, "#{t.line}: #{Parser.render(done.(t))}#{recur_note}"}
    end
  end

  def run(_, _), do: {:usage, "todo do ITEM#"}

  defp append_recurrence(t, tasks, paths, today) do
    case Task.next_recurrence(t, today) do
      nil ->
        {:ok, ""}

      new ->
        # Interior blank lines make `length(tasks)` smaller than the
        # real last line number — number past the max existing line.
        new = %{new | line: (tasks |> Enum.map(& &1.line) |> Enum.max(fn -> 0 end)) + 1}

        case Store.append(paths.todo, [new]) do
          :ok -> {:ok, "\n#{new.line}: #{Parser.render(new)}"}
          {:error, m} -> {:error, m}
        end
    end
  end
end
