defmodule TodoTxt.Commands.Pri do
  @moduledoc """
  `todo pri ITEM# A-Z` — set a task's priority.

  Rejects done tasks and priorities outside `A-Z`.
  """

  alias TodoTxt.{Commands.Helpers, Parser, Store, Task}

  def run([n, p], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         :ok <- valid_priority(t, p),
         new = Task.set_priority(t, :binary.first(p)),
         :ok <- Store.write(paths.todo, Helpers.replace(tasks, new)) do
      {:ok, "#{t.line}: #{Parser.render(new)}"}
    end
  end

  def run(_, _), do: {:usage, "todo pri ITEM# A-Z"}

  defp valid_priority(t, <<c>>) when c in ?A..?Z do
    if t.done, do: {:error, "task #{t.line} is already done"}, else: :ok
  end

  defp valid_priority(_, p), do: {:error, "invalid priority #{inspect(p)} (A-Z)"}
end
