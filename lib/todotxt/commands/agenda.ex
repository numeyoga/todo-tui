defmodule TodoTxt.Commands.Agenda do
  @moduledoc """
  `todo agenda` — list open tasks due within the next 14 days,
  grouped under `YYYY-MM-DD:` date headers in chronological
  order. Overdue and done tasks are excluded.
  """

  alias TodoTxt.{Format, Query}

  @days 14

  def run(_, %{tasks: tasks, today: today, opts: opts}) do
    horizon = Date.add(today, @days)

    groups =
      tasks
      |> Enum.reject(& &1.done)
      |> Enum.group_by(&Query.due_date/1)
      |> Enum.reject(fn {d, _} ->
        is_nil(d) or Date.compare(d, today) == :lt or Date.compare(d, horizon) == :gt
      end)
      |> Enum.sort_by(fn {d, _} -> d end, Date)
      |> Enum.map(fn {d, ts} -> "#{d}:\n" <> Format.tasks(Query.sort(ts), opts) end)

    {:ok, Enum.join(groups, "\n\n")}
  end
end
