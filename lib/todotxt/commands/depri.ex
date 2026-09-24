defmodule TodoTxt.Commands.Depri do
  @moduledoc """
  `todo depri ITEM#` — remove a task's priority.
  """

  alias TodoTxt.{Commands.Helpers, Tasks}

  def run([n], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, _} <- Tasks.set_priority(paths.todo, tasks, t, nil) do
      {:ok, "#{t.line}: deprioritized"}
    end
  end

  def run(_, _), do: {:usage, "todo depri ITEM#"}
end
