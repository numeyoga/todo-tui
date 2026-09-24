defmodule TodoTxt.Commands.Undo do
  @moduledoc """
  `todo undo ITEM#` — reopen a done task.

  Clears `done` and `completion_date`.
  """

  alias TodoTxt.{Commands.Helpers, Parser, Tasks}

  def run([n | _], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, %{task: reopened}} <- Tasks.uncomplete(paths, tasks, t) do
      {:ok, "#{t.line}: #{Parser.render(reopened)}"}
    end
  end

  def run(_, _), do: {:usage, "todo undo ITEM#"}
end
