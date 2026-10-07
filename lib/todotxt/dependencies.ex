defmodule TodoTxt.Dependencies do
  @moduledoc """
  Manages task dependencies based on `id:` and `dep:` / `p:` tags.
  """

  alias TodoTxt.Task

  @doc "Extracts list of dependency IDs referenced in dep: or p: tags (comma separated)."
  def parse_deps(%Task{} = t) do
    tags = t.tags
    raw_deps = tags["dep"] || tags["p"]

    case raw_deps do
      nil ->
        []

      str when is_binary(str) ->
        str
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  @doc "Finds all blocking tasks or dependency IDs that are not marked done."
  def blocking_tasks(%Task{} = t, all_tasks) when is_list(all_tasks) do
    dep_ids = parse_deps(t)

    if dep_ids == [] do
      []
    else
      id_map = build_task_map(all_tasks)

      dep_ids
      |> Enum.filter(fn dep_id ->
        case Map.get(id_map, dep_id) do
          nil -> true
          dep_task -> not dep_task.done
        end
      end)
      |> Enum.map(fn dep_id ->
        case Map.get(id_map, dep_id) do
          nil -> dep_id
          dep_task -> dep_task
        end
      end)
    end
  end

  @doc "Returns true if the task has uncompleted dependencies."
  def blocked?(%Task{} = t, all_tasks) do
    blocking_tasks(t, all_tasks) != []
  end

  defp build_task_map(all_tasks) do
    Enum.reduce(all_tasks, %{}, fn task, acc ->
      acc =
        case task.tags["id"] do
          nil -> acc
          id_val -> Map.put(acc, id_val, task)
        end

      Map.put(acc, to_string(task.line), task)
    end)
  end
end
