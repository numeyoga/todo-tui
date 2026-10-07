defmodule TodoTxt.Notes do
  @moduledoc """
  Manages external task notes (`note:` tag convention).

  Notes are text/markdown files stored in a `notes/` subdirectory
  adjacent to the active `todo.txt` file.
  """

  alias TodoTxt.Task

  @doc "Returns the notes directory path for the given todo.txt path."
  def dir(todo_path) do
    Path.join(Path.dirname(todo_path), "notes")
  end

  @doc "Returns the absolute path to a note file given todo.txt path and note filename."
  def note_path(todo_path, filename) do
    Path.join(dir(todo_path), filename)
  end

  @doc """
  Ensures a note file exists for `task`.

  Returns `{note_path, updated_task_or_nil}`. If `task` already has a `note:` tag,
  `updated_task_or_nil` is `nil`. If the task did not have a `note:` tag,
  a filename is generated (`task_<line>.txt`), attached via `Task.append_text/2`,
  and returned as the second element of the tuple.
  """
  def ensure_note_file(todo_path, %Task{} = task) do
    notes_dir = dir(todo_path)
    File.mkdir_p!(notes_dir)

    {filename, updated_task} =
      case task.tags["note"] do
        nil ->
          name = default_filename(task)
          new_t = Task.append_text(task, "note:#{name}")
          {name, new_t}

        existing_name ->
          {existing_name, nil}
      end

    path = Path.join(notes_dir, filename)

    if not File.exists?(path) do
      header = "# Note pour la tâche #{task.line}\n# #{task.description}\n\n"
      File.write!(path, header)
    end

    {path, updated_task}
  end

  @doc "Reads the content of a task's note file, or {:error, reason}."
  def read(todo_path, %Task{} = task) do
    case task.tags["note"] do
      nil ->
        {:error, :no_note_tag}

      filename ->
        path = note_path(todo_path, filename)

        if File.exists?(path) do
          File.read(path)
        else
          {:error, :file_not_found}
        end
    end
  end

  defp default_filename(%Task{line: line}) do
    "task_#{line}.txt"
  end
end
