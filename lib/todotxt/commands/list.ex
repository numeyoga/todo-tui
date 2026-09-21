defmodule TodoTxt.Commands.List do
  @moduledoc """
  `todo ls [TERMS...]` — list visible tasks, filtered by TERMS
  (AND) and sorted by priority then line. Numbers shown are the
  file line numbers, stable under filtering.
  """

  alias TodoTxt.{Format, Query}

  def run(terms, %{tasks: tasks, today: today, opts: opts}) do
    shown = tasks |> Query.visible(today) |> Query.filter(terms) |> sort(opts)
    {:ok, Format.render(shown, opts)}
  end

  # `LS_SORT=line` (config file) sorts by line only, ignoring priority.
  defp sort(tasks, opts) do
    if Map.get(opts, :sort) == "line",
      do: Enum.sort_by(tasks, & &1.line),
      else: Query.sort(tasks)
  end
end
