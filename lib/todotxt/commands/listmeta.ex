defmodule TodoTxt.Commands.ListMeta do
  @moduledoc """
  `todo listproj` / `listcon` / `listpri A-Z` — list unique projects
  and contexts across both files, or the tasks carrying a given
  priority (todo.txt only).
  """

  alias TodoTxt.Format

  def run(["proj" | _], ctx), do: list(ctx, & &1.projects)
  def run(["con" | _], ctx), do: list(ctx, & &1.contexts)

  def run(["pri", p], ctx) do
    with [c] <- String.to_charlist(p), true <- c in ?A..?Z do
      shown = ctx.tasks |> Enum.filter(&(&1.priority == c)) |> TodoTxt.Query.sort()
      {:ok, Format.tasks(shown, ctx.opts)}
    else
      _ -> {:usage, "todo listpri A-Z"}
    end
  end

  def run(_, _), do: {:usage, "todo listproj|listcon|listpri [A-Z]"}

  defp list(%{tasks: t, done_tasks: d, opts: opts}, fun) do
    vals = (t ++ d) |> Enum.flat_map(fun) |> Enum.uniq() |> Enum.sort()

    {:ok,
     if(opts.json,
       do: Jason.encode!(vals, pretty: true),
       else: Enum.join(vals, "\n")
     )}
  end
end
