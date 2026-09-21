defmodule TodoTxt.Commands.Edit do
  @moduledoc """
  `todo edit` — open todo.txt in `$EDITOR` (defaults to `vi`).

  The editor inherits the terminal. A missing editor binary or a
  non-zero exit status is reported as an error.
  """

  def run(_args, %{paths: paths}) do
    editor = System.get_env("EDITOR") || "vi"

    try do
      case System.cmd(editor, [paths.todo], into: IO.stream(:stdio, :line)) do
        {_, 0} -> {:ok, "edited #{paths.todo}"}
        {_, code} -> {:error, "editor exited #{code}"}
      end
    rescue
      ErlangError -> {:error, "editor not found: #{editor}"}
    end
  end
end
