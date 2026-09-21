defmodule TodoTxt.Commands.Agenda do
  @moduledoc """
  `todo agenda` — list open tasks due within the next 14 days,
  grouped under `YYYY-MM-DD:` date headers in chronological
  order, followed by a `THRESHOLDS:` section of open tasks
  whose `t:` threshold date falls in the same window.
  Overdue and done tasks are excluded.
  """

  alias TodoTxt.{Format, Ops, Query}

  def run(_, %{tasks: tasks, today: today, opts: opts}) do
    {groups, thresholds} = Ops.agenda(tasks, today)

    if opts.json do
      dates =
        Map.new(groups, fn {d, ts} ->
          {Date.to_string(d), Enum.map(Query.sort(ts), &Format.task_map/1)}
        end)

      {:ok,
       Jason.encode!(
         %{dates: dates, thresholds: Enum.map(thresholds, &Format.task_map/1)},
         pretty: true
       )}
    else
      sections =
        Enum.map(groups, fn {d, ts} -> "#{d}:\n" <> Format.tasks(Query.sort(ts), opts) end)

      sections =
        if thresholds == [],
          do: sections,
          else: sections ++ ["THRESHOLDS:\n" <> Format.tasks(thresholds, opts)]

      {:ok, Enum.join(sections, "\n\n")}
    end
  end
end
