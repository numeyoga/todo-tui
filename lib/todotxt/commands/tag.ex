defmodule TodoTxt.Commands.Tag do
  @moduledoc """
  `todo tag ITEM# KEY VALUE` or `todo tag ITEM# KEY:VALUE...` — add or update tags on a task.
  """

  alias TodoTxt.Commands.Helpers
  alias TodoTxt.{Parser, Task, Tasks}

  def run([n, k, v | rest], %{tasks: tasks, paths: paths} = ctx) when not is_nil(v) do
    if String.contains?(k, ":") do
      parse_and_apply(n, [k, v | rest], ctx, paths, tasks)
    else
      with {:ok, t} <- Helpers.fetch(tasks, n) do
        apply_tags(ctx, paths, tasks, t, [{k, v} | parse_rest(rest)])
      end
    end
  end

  def run([n, kv | rest], %{tasks: tasks, paths: paths} = ctx) do
    parse_and_apply(n, [kv | rest], ctx, paths, tasks)
  end

  def run(_, _), do: {:usage, "todo tag ITEM# KEY VALUE [KEY:VALUE...]"}

  defp parse_and_apply(n, items, ctx, paths, tasks) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         {:ok, pairs} <- parse_pairs(items) do
      apply_tags(ctx, paths, tasks, t, pairs)
    else
      :error -> {:usage, "todo tag ITEM# KEY VALUE ou KEY:VALUE"}
      {:error, m} -> {:error, m}
    end
  end

  defp parse_pairs(items) do
    pairs =
      Enum.map(items, fn item ->
        case String.split(item, ":", parts: 2) do
          [k, v] when k != "" and v != "" -> {k, v}
          _ -> nil
        end
      end)

    if Enum.all?(pairs, &(&1 != nil)) and pairs != [], do: {:ok, pairs}, else: :error
  end

  defp parse_rest(rest) do
    case parse_pairs(rest) do
      {:ok, pairs} -> pairs
      _ -> []
    end
  end

  defp apply_tags(ctx, paths, tasks, t, pairs) do
    new_t =
      Enum.reduce(pairs, t, fn {k, v}, acc ->
        Task.put_tag(acc, k, v)
      end)

    io = Map.get(ctx, :io, Tasks.default_io())

    with {:ok, %{task: updated}} <-
           Tasks.replace_text(io, paths.todo, tasks, t, Parser.render(new_t)) do
      {:ok, "#{updated.line}: #{Parser.render(updated)}"}
    end
  end
end
