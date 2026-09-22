defmodule TodoTxt.Commands.Edit do
  @moduledoc """
  `todo edit` — open todo.txt in `$VISUAL`/`$EDITOR` (defaults to `vi`).

  The editor inherits the terminal (see `TodoTxt.Editor`); a missing
  binary or a non-zero exit status is reported as an error.
  """

  def run(_args, %{paths: paths}) do
    case TodoTxt.Editor.open(paths.todo) do
      :ok -> {:ok, "edited #{paths.todo}"}
      {:error, m} -> {:error, m}
    end
  end
end
