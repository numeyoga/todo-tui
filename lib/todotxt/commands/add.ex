defmodule TodoTxt.Commands.Add do
  @moduledoc """
  `todo add "TASK"` — append a new task to todo.txt.

  Prepends today's creation date, assigns the next line number and
  echoes the rendered task back.
  """

  alias TodoTxt.{Parser, Tasks}

  def run([], _), do: {:usage, "todo add \"TASK\""}

  def run(words, %{paths: paths, tasks: tasks, today: today}) do
    with {:ok, %{task: task}} <- Tasks.add(paths, tasks, Enum.join(words, " "), today) do
      {:ok, "#{task.line}: #{Parser.render(task)}"}
    end
  end
end
