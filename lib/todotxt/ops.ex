defmodule TodoTxt.Ops do
  @moduledoc """
  Pure task-list operations shared by `TodoTxt.Commands.*` (CLI) and
  `TodoTxt.Tui`. No I/O, no output strings — callers write via
  `Store` and format their own feedback.
  """

  alias TodoTxt.{Commands.Helpers, Parser, Query, Task}

  @days 14

  @doc "Next free line number (`max(line) + 1`, 1 on empty list)."
  def next_line(tasks), do: (tasks |> Enum.map(& &1.line) |> Enum.max(fn -> 0 end)) + 1

  @doc "New task appended at `next_line/1`, creation date = today (after a leading `(X)`)."
  @spec add([Task.t()], String.t(), Date.t()) :: Task.t()
  def add(tasks, text, today), do: Parser.parse(with_date(text, today), next_line(tasks))

  defp with_date(text, today) do
    date = Date.to_string(today)

    case String.split(text, ~r/\s+/, trim: true) do
      [first | rest] ->
        if Regex.match?(~r/^\([A-Z]\)$/, first),
          do: Enum.join([first, date | rest], " "),
          else: Enum.join([date, first | rest], " ")

      [] ->
        date
    end
  end

  @doc """
  Mark `t` done today. Returns `{new_tasks, recur}` where `recur` is the
  next occurrence (line still 0 — caller assigns `next_line/1`) or nil.
  A present-but-malformed `recur:` tag is an error; nothing mutates.
  """
  @spec complete([Task.t()], Task.t(), Date.t()) ::
          {:ok, [Task.t()], Task.t() | nil} | {:error, String.t()}
  def complete(tasks, t, today) do
    case t.tags["recur"] do
      nil ->
        finish_complete(tasks, t, today)

      v ->
        if Task.next_recurrence(t, today) do
          finish_complete(tasks, t, today)
        else
          {:error, "invalid recur: #{inspect(v)} on task #{t.line}"}
        end
    end
  end

  defp finish_complete(tasks, t, today) do
    {:ok, Helpers.replace(tasks, Task.complete(t, today)), Task.next_recurrence(t, today)}
  end

  @spec uncomplete([Task.t()], Task.t()) :: {:ok, [Task.t()]}
  def uncomplete(tasks, t), do: {:ok, Helpers.replace(tasks, Task.uncomplete(t))}

  @spec delete([Task.t()], Task.t()) :: {:ok, [Task.t()]}
  def delete(tasks, t), do: {:ok, Enum.reject(tasks, &(&1.line == t.line))}

  @doc "Strip every whitespace-separated `term` token from `t`'s description."
  @spec delete_term([Task.t()], Task.t(), String.t()) :: {:ok, [Task.t()]}
  def delete_term(tasks, t, term) do
    desc = t.description |> String.split(~r/\s+/) |> Enum.reject(&(&1 == term)) |> Enum.join(" ")
    {:ok, Helpers.replace(tasks, Task.set_text(t, desc))}
  end

  @doc "Set priority `?A..?Z`, or nil to remove. Errors on done tasks / bad input."
  @spec set_priority([Task.t()], Task.t(), non_neg_integer() | nil) ::
          {:ok, [Task.t()]} | {:error, String.t()}
  def set_priority(tasks, t, nil), do: {:ok, Helpers.replace(tasks, Task.set_priority(t, nil))}

  def set_priority(tasks, t, c) when is_integer(c) do
    cond do
      c not in ?A..?Z -> {:error, "invalid priority #{inspect(<<c>>)} (A-Z)"}
      t.done -> {:error, "task #{t.line} is already done"}
      true -> {:ok, Helpers.replace(tasks, Task.set_priority(t, c))}
    end
  end

  @doc "Replace `t`'s whole line — reparsed, so `x`/`(A)`/dates are honored."
  @spec replace_text([Task.t()], Task.t(), String.t()) :: {:ok, [Task.t()]}
  def replace_text(tasks, t, text),
    do: {:ok, Helpers.replace(tasks, Parser.parse(text, t.line))}

  @spec append_text([Task.t()], Task.t(), String.t()) :: {:ok, [Task.t()]}
  def append_text(tasks, t, text),
    do: {:ok, Helpers.replace(tasks, Task.append_text(t, text))}

  @spec prepend_text([Task.t()], Task.t(), String.t()) :: {:ok, [Task.t()]}
  def prepend_text(tasks, t, text),
    do: {:ok, Helpers.replace(tasks, Task.prepend_text(t, text))}

  @doc "`{open, done}` — done tasks to append to done.txt, open to rewrite."
  @spec archive([Task.t()]) :: {[Task.t()], [Task.t()]}
  def archive(tasks), do: tasks |> Enum.split_with(& &1.done) |> then(fn {d, o} -> {o, d} end)

  @spec dedupe([Task.t()]) :: [Task.t()]
  def dedupe(tasks), do: Enum.uniq_by(tasks, & &1.raw)

  @doc """
  `{groups, thresholds}` for the next #{@days} days: open tasks grouped by
  `due:` (sorted by date), then open tasks whose `t:` falls in the window.
  Overdue and done tasks are excluded — same data as `Commands.Agenda`.
  """
  @spec agenda([Task.t()], Date.t()) :: {[{Date.t(), [Task.t()]}], [Task.t()]}
  def agenda(tasks, today) do
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

    {groups, thresholds}
  end

  defp threshold_date(t) do
    case t.tags["t"] && Date.from_iso8601(t.tags["t"]) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
