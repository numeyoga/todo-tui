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
    task = Parser.parse(with_date(words, today), line)

    case Store.append(paths.todo, [task]) do
      :ok -> {:ok, "#{line}: #{Parser.render(task)}"}
      {:error, m} -> {:error, m}
    end
  end

  # The creation date goes after a leading "(X)" priority token,
  # like todo.sh — "(A) text" becomes "(A) <today> text". Args may
  # arrive as one quoted string, so split the joined text first.
  defp with_date(words, today) do
    tokens = words |> Enum.join(" ") |> String.split(~r/\s+/, trim: true)
    date = Date.to_string(today)

    case tokens do
      [first | rest] when first != "" ->
        if Regex.match?(~r/^\([A-Z]\)$/, first),
          do: Enum.join([first, date | rest], " "),
          else: Enum.join([date | tokens], " ")
    end
  end
end
