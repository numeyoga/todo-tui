defmodule TodoTxt.Commands.Archive do
  @moduledoc """
  `todo archive` — move done tasks from todo.txt to done.txt.

  Done tasks are appended to done.txt (created if needed), then
  todo.txt is rewritten with only the open tasks.
  """

  alias TodoTxt.{Ops, Store}

  def run(_args, %{tasks: tasks, paths: paths}) do
    {open, done} = Ops.archive(tasks)

    with :ok <- append_done(paths.done, done),
         :ok <- Store.write(paths.todo, open) do
      {:ok, "archived #{length(done)} tasks"}
    end
  end

  defp append_done(_path, []), do: :ok
  defp append_done(path, done), do: Store.append(path, done)
end
