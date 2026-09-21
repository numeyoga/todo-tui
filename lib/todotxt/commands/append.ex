defmodule TodoTxt.Commands.Append do
  @moduledoc """
  `todo append ITEM# TEXT...` — append text to a task's description.
  """

  alias TodoTxt.{Commands.Helpers, Parser, Store, Task}

  def run([n | [_ | _] = words], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         new = Task.append_text(t, Enum.join(words, " ")),
         :ok <- Store.write(paths.todo, Helpers.replace(tasks, new)) do
      {:ok, "#{t.line}: #{Parser.render(new)}"}
    end
  end

  def run(_, _), do: {:usage, "todo append ITEM# TEXT..."}
end
