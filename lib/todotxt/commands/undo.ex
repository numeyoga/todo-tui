defmodule TodoTxt.Commands.Undo do
  @moduledoc """
  `todo undo ITEM#` — reopen a done task.

  Clears `done` and `completion_date`.
  """

  alias TodoTxt.{Commands.Helpers, Ops, Parser, Store, Task}

  def run([n | _], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, ts} <- Ops.uncomplete(tasks, t),
         :ok <- Store.write(paths.todo, ts) do
      {:ok, "#{t.line}: #{Parser.render(Task.uncomplete(t))}"}
    end
  end

  def run(_, _), do: {:usage, "todo undo ITEM#"}
end
