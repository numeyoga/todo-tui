defmodule TodoTxt.Commands.Agenda do
  @moduledoc """
  `todo agenda` — list open tasks due within the next 14 days,
  grouped under `YYYY-MM-DD:` date headers in chronological
  order, followed by a `THRESHOLDS:` section of open tasks
  whose `t:` threshold date falls in the same window.
  Overdue and done tasks are excluded.
  """

  alias TodoTxt.{Format, Query}

  @days 14

  def run(_, %{tasks: tasks, today: today, opts: opts}) do
    horizon = Date.add(today, @days)
    open = Enum.reject(tasks, & &1.done)

    in_range? = fn d ->
      not is_nil(d) and Date.compare(d, today) != :lt and Date.compare(d, horizon) != :gt
    end

    groups =
      open
      |> Enum.group_by(&Query.due_date/1)
      |> Enum.reject(fn {d, _} -> not in_range?.(d) end)
      |> Enum.sort_by(fn {d, _} -> d end, Date)

    thresholds =
      open
      |> Enum.filter(&in_range?.(threshold_date(&1)))
      |> Enum.sort_by(& &1.line)

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

  defp threshold_date(t) do
    case t.tags["t"] && Date.from_iso8601(t.tags["t"]) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
