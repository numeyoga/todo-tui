defmodule TodoTxt.Commands.ListAll do
  @moduledoc """
  `todo listall` — list every task from both `todo.txt` and
  `done.txt`, sorted by priority then line number.
  """

  alias TodoTxt.{Format, Query}

  def run(_, %{tasks: tasks, done_tasks: done_tasks, opts: opts}) do
    shown = Query.sort(tasks ++ done_tasks)
    {:ok, Format.render(shown, opts)}
  end
end
