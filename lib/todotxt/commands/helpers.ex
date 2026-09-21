defmodule TodoTxt.Commands.Helpers do
  @moduledoc """
  Shared helpers for commands operating on numbered tasks.

  Task numbers are file line numbers (`Task.line`), stable under
  filtering — not positions in a displayed list.
  """

  alias TodoTxt.Task

  @doc """
  Resolve a `n` string ("3") to the task whose `line` is 3.

  Returns `{:ok, task}` or `{:error, msg}` for unparsable or
  out-of-range numbers.
  """
  @spec fetch([Task.t()], String.t()) :: {:ok, Task.t()} | {:error, String.t()}
  def fetch(tasks, n) do
    case Integer.parse(n) do
      {i, ""} ->
        case Enum.find(tasks, &(&1.line == i)) do
          nil -> {:error, "no task #{n}"}
          t -> {:ok, t}
        end

      _ ->
        {:error, "invalid task number #{inspect(n)}"}
    end
  end

  @doc "Replace, in `tasks`, the task sharing `new.line` by `new`."
  @spec replace([Task.t()], Task.t()) :: [Task.t()]
  def replace(tasks, new), do: Enum.map(tasks, &if(&1.line == new.line, do: new, else: &1))
end
