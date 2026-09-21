defmodule TodoTxt.Commands.Depri do
  @moduledoc """
  `todo depri ITEM#` — remove a task's priority.
  """

  alias TodoTxt.{Commands.Helpers, Store, Task}

  def run([n], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         :ok <- Store.write(paths.todo, Helpers.replace(tasks, Task.set_priority(t, nil))) do
      {:ok, "#{t.line}: deprioritized"}
    end
  end

  def run(_, _), do: {:usage, "todo depri ITEM#"}
end
