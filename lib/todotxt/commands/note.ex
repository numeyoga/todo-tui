defmodule TodoTxt.Commands.Note do
  @moduledoc """
  `todo note [show|edit] ITEM#` — view or edit an external note file for a task.

  If no action is given:
    * Displays note content if it exists.
    * If no note exists or `--edit` is passed, opens it in `$EDITOR`.
  """

  alias TodoTxt.Commands.Helpers
  alias TodoTxt.{Editor, Notes, Tasks}

  def run(["show", n | _], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n) do
      case Notes.read(paths.todo, t) do
        {:ok, content} ->
          {:ok, String.trim_trailing(content)}

        {:error, :no_note_tag} ->
          {:ok, "Aucune note associée à la tâche #{t.line}"}

        {:error, :file_not_found} ->
          {:ok, "Le fichier de note '#{t.tags["note"]}' n'existe pas"}
      end
    end
  end

  def run(["edit", n | _], %{tasks: tasks, paths: paths} = ctx) do
    with {:ok, t} <- Helpers.fetch(tasks, n) do
      {note_path, updated_t} = Notes.ensure_note_file(paths.todo, t)

      _ =
        if updated_t do
          io = Map.get(ctx, :io, Tasks.default_io())
          Tasks.replace_text(io, paths.todo, tasks, t, updated_t.raw)
        end

      case Editor.edit(note_path) do
        :ok -> {:ok, "Note mise à jour : #{note_path}"}
        {:error, m} -> {:error, m}
      end
    end
  end

  def run([n | _], %{opts: %{edit: true}} = ctx), do: run(["edit", n], ctx)

  def run([n | _], %{tasks: tasks, paths: paths} = ctx) do
    with {:ok, t} <- Helpers.fetch(tasks, n), do: read_or_edit_note(paths.todo, t, n, ctx)
  end

  def run(_, _), do: {:usage, "todo note [show|edit] ITEM#"}

  defp read_or_edit_note(todo_path, t, n, ctx) do
    case Notes.read(todo_path, t) do
      {:ok, content} -> {:ok, String.trim_trailing(content)}
      _ -> run(["edit", n], ctx)
    end
  end
end
