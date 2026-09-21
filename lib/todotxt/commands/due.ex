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
        if ts == [], do: nil, else: "#{header}:\n" <> Format.tasks(ts, opts)
      end

    {:ok, groups |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")}
  end
end
