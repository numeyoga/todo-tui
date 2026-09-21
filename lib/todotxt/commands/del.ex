defmodule TodoTxt.Commands.Del do
  @moduledoc """
  `todo del ITEM# [TERM]` — delete a task, or strip a term.

  Without TERM, removes the whole line. With TERM, removes every
  occurrence of that whitespace-separated token from the task's
  description (e.g. `todo del 2 +proj`).
  """

  alias TodoTxt.{Commands.Helpers, Ops, Parser, Store}

  def run([n], ctx), do: delete(ctx, n, nil)
  def run([n, term], ctx), do: delete(ctx, n, term)
  def run(_, _), do: {:usage, "todo del ITEM# [TERM]"}

  defp delete(%{tasks: tasks, paths: paths}, n, nil) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, ts} <- Ops.delete(tasks, t),
         :ok <- Store.write(paths.todo, ts) do
      {:ok, "#{t.line}: deleted #{t.raw}"}
    end
  end

  defp delete(%{tasks: tasks, paths: paths}, n, term) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, ts} <- Ops.delete_term(tasks, t, term),
         :ok <- Store.write(paths.todo, ts) do
      new = Enum.find(ts, &(&1.line == t.line))
      {:ok, "#{t.line}: #{Parser.render(new)}"}
    end
  end
end
