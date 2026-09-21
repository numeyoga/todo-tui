defmodule TodoTxt.Commands.Due do
  @moduledoc """
  `todo due` — list open tasks grouped by due-date bucket:
  OVERDUE, TODAY, THIS WEEK (next 7 days), LATER. Done tasks
  and tasks without a valid `due:` tag are excluded.
  """

  alias TodoTxt.{Format, Query}

  @buckets [overdue: "OVERDUE", today: "TODAY", week: "THIS WEEK", later: "LATER"]

  def run(_, %{tasks: tasks, today: today, opts: opts}) do
    open = Enum.reject(tasks, & &1.done)

    groups =
      for {bucket, header} <- @buckets do
        ts = open |> Enum.filter(&(Query.due_bucket(&1, today) == bucket)) |> Query.sort()
        {bucket, header, ts}
      end

    if opts.json do
      maps =
        for {bucket, _header, ts} <- groups,
            t <- ts,
            do: Map.put(Format.task_map(t), :bucket, bucket)

      {:ok, Jason.encode!(maps, pretty: true)}
    else
      text =
        groups
        |> Enum.reject(fn {_b, _h, ts} -> ts == [] end)
        |> Enum.map_join("\n\n", fn {_b, header, ts} ->
          "#{header}:\n" <> Format.tasks(ts, opts)
        end)

      {:ok, text}
    end
  end
end
