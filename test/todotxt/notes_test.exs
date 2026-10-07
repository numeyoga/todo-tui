defmodule TodoTxt.NotesTest do
  use ExUnit.Case, async: true

  alias TodoTxt.{Notes, Parser}

  @tmp_dir System.tmp_dir!()

  setup do
    dir = Path.join(@tmp_dir, "todo_notes_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    todo_path = Path.join(dir, "todo.txt")
    File.write!(todo_path, "")

    on_exit(fn -> File.rm_rf(dir) end)

    %{todo_path: todo_path, dir: dir}
  end

  test "ensure_note_file creates a default note file and appends note: tag if absent", %{
    todo_path: todo_path
  } do
    t = Parser.parse("Buy milk", 5)

    {note_path, updated_t} = Notes.ensure_note_file(todo_path, t)

    assert File.exists?(note_path)
    assert Path.basename(note_path) == "task_5.txt"
    assert updated_t != nil
    assert updated_t.tags["note"] == "task_5.txt"
    assert File.read!(note_path) =~ "# Note pour la tâche 5"
  end

  test "ensure_note_file respects existing note: tag without modifying task", %{
    todo_path: todo_path
  } do
    t = Parser.parse("Review design note:design_spec.md", 2)

    {note_path, updated_t} = Notes.ensure_note_file(todo_path, t)

    assert File.exists?(note_path)
    assert Path.basename(note_path) == "design_spec.md"
    assert updated_t == nil
  end

  test "read returns content or error", %{todo_path: todo_path} do
    t_no_tag = Parser.parse("No note", 1)
    assert Notes.read(todo_path, t_no_tag) == {:error, :no_note_tag}

    t_missing = Parser.parse("Missing note:ghost.txt", 2)
    assert Notes.read(todo_path, t_missing) == {:error, :file_not_found}

    {note_path, _} = Notes.ensure_note_file(todo_path, t_missing)
    File.write!(note_path, "Important note content")

    assert Notes.read(todo_path, t_missing) == {:ok, "Important note content"}
  end
end
