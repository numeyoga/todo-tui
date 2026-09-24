defmodule TodoTxt.Commands.Dedupe do
  @moduledoc """
  `todo dedupe` — remove duplicate lines from todo.txt.

  Comparison is on the raw line text; the first occurrence wins.
  todo.txt is rewritten in place.
  """

  alias TodoTxt.Tasks

  def run(_args, %{tasks: tasks, paths: paths}) do
    with {:ok, %{removed: removed}} <- Tasks.dedupe(paths.todo, tasks) do
      {:ok, "removed #{removed} duplicates"}
    end
  end
end
