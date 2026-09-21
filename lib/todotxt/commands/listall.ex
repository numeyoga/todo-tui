defmodule TodoTxt.Commands.ListAll do
  @moduledoc """
  `todo listall` — list every task from both `todo.txt` and
  `done.txt`, sorted by priority then line number.
  """

  alias TodoTxt.{Format, Query}

  def run(_, %{tasks: tasks, done_tasks: done_tasks, opts: opts}) do
    shown = Query.sort(tasks ++ done_tasks)

    {:ok,
     if(opts.json,
       do: Jason.encode!(Enum.map(shown, &Format.task_map/1), pretty: true),
       else: Format.tasks(shown, opts)
     )}
  end
end
