defmodule TodoTxt.Commands.Depri do
  @moduledoc """
  `todo depri ITEM#` — remove a task's priority.
  """

  alias TodoTxt.{Commands.Helpers, Ops, Store}

  def run([n], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, ts} <- Ops.set_priority(tasks, t, nil),
         :ok <- Store.write(paths.todo, ts) do
      {:ok, "#{t.line}: deprioritized"}
    end
  end

  def run(_, _), do: {:usage, "todo depri ITEM#"}
end
