defmodule TodoTxt.Commands.List do
  @moduledoc """
  `todo ls [TERMS...]` — list visible tasks, filtered by TERMS
  (AND) and sorted by priority then line. Numbers shown are the
  file line numbers, stable under filtering.
  """

  alias TodoTxt.{Format, Query}

  def run(terms, %{tasks: tasks, today: today, opts: opts}) do
    shown = tasks |> Query.visible(today) |> Query.filter(terms) |> Query.sort()

    {:ok,
     if(opts.json,
       do: Jason.encode!(Enum.map(shown, &Format.task_map/1), pretty: true),
       else: Format.tasks(shown, opts)
     )}
  end
end
