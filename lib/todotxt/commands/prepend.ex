defmodule TodoTxt.Commands.Prepend do
  @moduledoc """
  `todo prepend ITEM# TEXT...` — prepend text to a task's description.
  """

  alias TodoTxt.{Commands.Helpers, Ops, Parser, Store}

  def run([n | [_ | _] = words], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, ts} <- Ops.prepend_text(tasks, t, Enum.join(words, " ")),
         :ok <- Store.write(paths.todo, ts) do
      new = Enum.find(ts, &(&1.line == t.line))
      {:ok, "#{t.line}: #{Parser.render(new)}"}
    end
  end

  def run(_, _), do: {:usage, "todo prepend ITEM# TEXT..."}
end
