defmodule TodoTxt.Commands.Add do
  @moduledoc """
  `todo add "TASK"` — append a new task to todo.txt.

  Prepends today's creation date, assigns the next line number and
  echoes the rendered task back.
  """

  alias TodoTxt.{Parser, Store}

  def run([], _), do: {:usage, "todo add \"TASK\""}

  def run(words, %{paths: paths, tasks: tasks, today: today}) do
    line = (tasks |> Enum.map(& &1.line) |> Enum.max(fn -> 0 end)) + 1
    task = Parser.parse(Enum.join([Date.to_string(today) | words], " "), line)

    case Store.append(paths.todo, [task]) do
      :ok -> {:ok, "#{line}: #{Parser.render(task)}"}
      {:error, m} -> {:error, m}
    end
  end
end
