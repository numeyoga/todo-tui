defmodule TodoTxt.Commands.Append do
  @moduledoc """
  `todo append ITEM# TEXT...` — append text to a task's description.
  """

  alias TodoTxt.{Commands.Helpers, Parser, Tasks}

  def run([n | [_ | _] = words], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, %{task: new}} <- Tasks.append_text(paths.todo, tasks, t, Enum.join(words, " ")) do
      {:ok, "#{t.line}: #{Parser.render(new)}"}
    end
  end

  def run(_, _), do: {:usage, "todo append ITEM# TEXT..."}
end
