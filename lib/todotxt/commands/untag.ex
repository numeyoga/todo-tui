defmodule TodoTxt.Commands.Untag do
  @moduledoc """
  `todo untag ITEM# KEY [KEY...]` — remove one or more tags from a task.
  """

  alias TodoTxt.Commands.Helpers
  alias TodoTxt.{Parser, Task, Tasks}

  def run([n, first_key | rest_keys], %{tasks: tasks, paths: paths} = ctx) do
    keys = [first_key | rest_keys]

    with {:ok, t} <- Helpers.fetch(tasks, n) do
      new_t =
        Enum.reduce(keys, t, fn key, acc ->
          k = String.trim_trailing(key, ":")
          Task.delete_tag(acc, k)
        end)

      io = Map.get(ctx, :io, Tasks.default_io())

      with {:ok, %{task: updated}} <-
             Tasks.replace_text(io, paths.todo, tasks, t, Parser.render(new_t)) do
        {:ok, "#{updated.line}: #{Parser.render(updated)}"}
      end
    end
  end

  def run(_, _), do: {:usage, "todo untag ITEM# KEY [KEY...]"}
end
