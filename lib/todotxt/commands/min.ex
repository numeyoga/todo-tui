defmodule TodoTxt.Commands.Min do
  @moduledoc """
  `todo min ITEM# [+|-]MINUTES` — add or set time spent on a task.

  Examples:
    * `todo min 1 45` — sets `min:45`
    * `todo min 1 +15` — adds 15 minutes to existing `min:`
  """

  alias TodoTxt.Commands.Helpers
  alias TodoTxt.{Parser, Tasks, TimeTracker}

  def run([n, delta_str | _], %{tasks: tasks, paths: paths} = ctx) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, new_total} <- calculate_new_minutes(t.tags["min"], delta_str) do
      new_desc = update_min_tag(t.description, new_total)
      new_t = %{t | description: new_desc}
      io = Map.get(ctx, :io, Tasks.default_io())

      with {:ok, %{task: updated}} <-
             Tasks.replace_text(io, paths.todo, tasks, t, Parser.render(new_t)) do
        formatted = TimeTracker.format_minutes(new_total)
        {:ok, "#{updated.line}: #{Parser.render(updated)} (total: #{formatted})"}
      end
    else
      :error -> {:error, "durée invalide : #{delta_str}"}
      {:error, m} -> {:error, m}
    end
  end

  def run(_, _), do: {:usage, "todo min ITEM# [+|-]MINUTES"}

  defp calculate_new_minutes(current_str, delta_str) do
    current =
      case current_str do
        nil -> 0
        s when is_binary(s) -> String.to_integer(s)
      end

    case delta_str do
      <<"+", rest::binary>> ->
        case Integer.parse(rest) do
          {add, ""} -> {:ok, current + add}
          _ -> :error
        end

      <<"-", rest::binary>> ->
        case Integer.parse(rest) do
          {sub, ""} -> {:ok, max(0, current - sub)}
          _ -> :error
        end

      val ->
        case Integer.parse(val) do
          {set, ""} -> {:ok, max(0, set)}
          _ -> :error
        end
    end
  rescue
    _ -> :error
  end

  defp update_min_tag(desc, mins) do
    re = ~r/\bmin:\S+/

    if Regex.match?(re, desc) do
      Regex.replace(re, desc, "min:#{mins}")
    else
      String.trim(desc <> " min:#{mins}")
    end
  end
end
