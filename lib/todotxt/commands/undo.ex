defmodule TodoTxt.Commands.Undo do
  @moduledoc """
  `todo undo ITEM#` — reopen a done task.

  Clears `done` and `completion_date`.
  """

  alias TodoTxt.{Commands.Helpers, Parser, Store, Task}

  def run([n | _], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         new = Task.uncomplete(t),
         :ok <- Store.write(paths.todo, Helpers.replace(tasks, new)) do
      {:ok, "#{t.line}: #{Parser.render(new)}"}
    end
  end

  def run(_, _), do: {:usage, "todo undo ITEM#"}
end
