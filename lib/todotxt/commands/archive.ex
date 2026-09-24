defmodule TodoTxt.Commands.Archive do
  @moduledoc """
  `todo archive` — move done tasks from todo.txt to done.txt.

  Done tasks are appended to done.txt (created if needed), then
  todo.txt is rewritten with only the open tasks.
  """

  alias TodoTxt.Tasks

  def run(_args, %{tasks: tasks, paths: paths}) do
    with {:ok, %{count: n}} <- Tasks.archive(paths, tasks) do
      {:ok, "archived #{n} tasks"}
    end
  end
end
