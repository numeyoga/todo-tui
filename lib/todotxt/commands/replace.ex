defmodule TodoTxt.Commands.Replace do
  @moduledoc """
  `todo replace ITEM# TEXT...` — replace a task's whole line.

  The given text is reparsed as a full todo.txt line, so a leading
  `x`, `(A)` priority or dates are honored.
  """

  alias TodoTxt.{Commands.Helpers, Parser, Store}

  def run([n | [_ | _] = words], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         new = Parser.parse(Enum.join(words, " "), t.line),
         :ok <- Store.write(paths.todo, Helpers.replace(tasks, new)) do
      {:ok, "#{t.line}: #{Parser.render(new)}"}
    end
  end

  def run(_, _), do: {:usage, "todo replace ITEM# TEXT..."}
end
