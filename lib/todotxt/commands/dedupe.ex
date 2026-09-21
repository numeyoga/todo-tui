defmodule TodoTxt.Commands.Dedupe do
  @moduledoc """
  `todo dedupe` — remove duplicate lines from todo.txt.

  Comparison is on the raw line text; the first occurrence wins.
  todo.txt is rewritten in place.
  """

  alias TodoTxt.{Ops, Store}

  def run(_args, %{tasks: tasks, paths: paths}) do
    uniq = Ops.dedupe(tasks)
    removed = length(tasks) - length(uniq)

    with :ok <- Store.write(paths.todo, uniq) do
      {:ok, "removed #{removed} duplicates"}
    end
  end
end
