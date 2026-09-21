defmodule TodoTxt.Commands.Add do
  @moduledoc """
  `todo add "TASK"` — append a new task to todo.txt.

  Prepends today's creation date, assigns the next line number and
  echoes the rendered task back.
  """

  alias TodoTxt.{Ops, Parser, Store}

  def run([], _), do: {:usage, "todo add \"TASK\""}

  def run(words, %{paths: paths, tasks: tasks, today: today}) do
    task = Ops.add(tasks, Enum.join(words, " "), today)

    case Store.append(paths.todo, [task]) do
      :ok -> {:ok, "#{task.line}: #{Parser.render(task)}"}
      {:error, m} -> {:error, m}
    end
  end
end
