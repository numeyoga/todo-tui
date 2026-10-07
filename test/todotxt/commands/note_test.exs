defmodule TodoTxt.Commands.NoteTest do
  use ExUnit.Case, async: true

  alias TodoTxt.{Commands.Note, Parser}

  @tmp_dir System.tmp_dir!()

  setup do
    dir = Path.join(@tmp_dir, "cmd_note_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    todo_path = Path.join(dir, "todo.txt")
    File.write!(todo_path, "")
    on_exit(fn -> File.rm_rf(dir) end)

    %{todo_path: todo_path, dir: dir}
  end

  test "show displays message if no note tag", %{todo_path: todo_path} do
    tasks = [Parser.parse("Test task", 1)]
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, msg} = Note.run(["show", "1"], ctx)
    assert msg =~ "Aucune note associée"
  end

  test "show displays note content when present", %{todo_path: todo_path, dir: dir} do
    notes_dir = Path.join(dir, "notes")
    File.mkdir_p!(notes_dir)
    File.write!(Path.join(notes_dir, "my_note.txt"), "Détails importants de la tâche")

    tasks = [Parser.parse("Test task note:my_note.txt", 1)]
    ctx = %{tasks: tasks, paths: %{todo: todo_path}, opts: %{}}

    assert {:ok, msg} = Note.run(["show", "1"], ctx)
    assert msg == "Détails importants de la tâche"

    # Default run without action also shows content if file exists
    assert {:ok, ^msg} = Note.run(["1"], ctx)
  end

  test "returns usage on invalid args", %{todo_path: todo_path} do
    ctx = %{tasks: [], paths: %{todo: todo_path}, opts: %{}}
    assert {:usage, _} = Note.run([], ctx)
  end
end
