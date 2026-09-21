defmodule TodoTxt.Query do
  @moduledoc """
  Pure queries over task lists: filter, sort and `t:`-threshold
  visibility. No I/O.
  """

  import Kernel, except: [match?: 2]

  @doc """
  Keeps tasks matching all `terms` (AND).

  A `+proj` term requires exact membership in `task.projects`,
  a `@ctx` term in `task.contexts`; any other term is a
  case-insensitive substring match on the raw line.
  """
  def filter(tasks, terms) do
    Enum.filter(tasks, fn t -> Enum.all?(terms, &match?(&1, t)) end)
  end

  defp match?(<<"+"::binary, _::binary>> = term, t), do: term in t.projects
  defp match?(<<"@"::binary, _::binary>> = term, t), do: term in t.contexts
  defp match?(term, t), do: String.contains?(String.downcase(t.raw), String.downcase(term))

  @doc "Sorts by priority ascending (no priority last), then line number."
  def sort(tasks), do: Enum.sort_by(tasks, &{&1.priority || 256, &1.line})

  @doc """
  Keeps tasks visible on `today`: done tasks are always shown,
  pending tasks are hidden while their `t:` threshold date is in
  the future.
  """
  def visible(tasks, today) do
    Enum.filter(tasks, fn t ->
      t.done ||
        case t.tags["t"] do
          nil ->
            true

          v ->
            case Date.from_iso8601(v) do
              {:ok, d} -> Date.compare(d, today) != :gt
              _ -> true
            end
        end
    end)
  end

  @doc "Parses the task's `due:` tag; nil when absent or invalid."
  def due_date(t) do
    case t.tags["due"] && Date.from_iso8601(t.tags["due"]) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  @doc """
  Classifies a task's due date relative to `today`:
  `:overdue`, `:today`, `:week` (within 7 days), `:later`,
  or `:none` (no valid `due:` tag).
  """
  def due_bucket(t, today) do
    case due_date(t) do
      nil ->
        :none

      d ->
        diff = Date.diff(d, today)

        cond do
          diff < 0 -> :overdue
          diff == 0 -> :today
          diff <= 7 -> :week
          true -> :later
        end
    end
  end
end
