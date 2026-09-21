defmodule TodoTxt.Commands.Del do
  @moduledoc """
  `todo del ITEM# [TERM]` — delete a task, or strip a term.

  Without TERM, removes the whole line. With TERM, removes every
  occurrence of that whitespace-separated token from the task's
  description (e.g. `todo del 2 +proj`).
  """

  alias TodoTxt.{Commands.Helpers, Parser, Store, Task}

  def run([n], ctx), do: delete(ctx, n, nil)
  def run([n, term], ctx), do: delete(ctx, n, term)
  def run(_, _), do: {:usage, "todo del ITEM# [TERM]"}

  defp delete(%{tasks: tasks, paths: paths}, n, nil) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         :ok <- Store.write(paths.todo, Enum.reject(tasks, &(&1.line == t.line))) do
      {:ok, "#{t.line}: deleted #{t.raw}"}
    end
  end

  defp delete(%{tasks: tasks, paths: paths}, n, term) do
    with {:ok, t} <- Helpers.fetch(tasks, n) do
      desc =
        t.description |> String.split(~r/\s+/) |> Enum.reject(&(&1 == term)) |> Enum.join(" ")

      new = Task.set_text(t, desc)

      with :ok <- Store.write(paths.todo, Helpers.replace(tasks, new)),
           do: {:ok, "#{t.line}: #{Parser.render(new)}"}
    end
  end
end
