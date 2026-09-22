defmodule TodoTxt.EditorTest do
  use ExUnit.Case

  alias TodoTxt.Editor

  describe "resolve/0" do
    setup do
      old = for v <- ["VISUAL", "EDITOR"], do: {v, System.get_env(v)}

      on_exit(fn ->
        for {v, val} <- old do
          if val, do: System.put_env(v, val), else: System.delete_env(v)
        end
      end)
    end

    test "VISUAL wins over EDITOR, vi is the fallback" do
      System.delete_env("VISUAL")
      System.delete_env("EDITOR")
      assert Editor.resolve() == "vi"

      System.put_env("EDITOR", "nano")
      assert Editor.resolve() == "nano"

      System.put_env("VISUAL", "vim")
      assert Editor.resolve() == "vim"
    end

    test "blank values count as unset" do
      System.put_env("VISUAL", "  ")
      System.put_env("EDITOR", "nano")
      assert Editor.resolve() == "nano"
    end
  end

  describe "split/1" do
    test "splits a command line into [bin | args]" do
      assert Editor.split("vim") == ["vim"]
      assert Editor.split("code --wait") == ["code", "--wait"]
      assert Editor.split("emacs -nw") == ["emacs", "-nw"]
    end

    test "honors quotes" do
      assert Editor.split(~s|"/opt/my editor/ed" -f|) == ["/opt/my editor/ed", "-f"]
    end
  end

  describe "open/2" do
    test "exit 0 returns :ok" do
      assert Editor.open("some/file", "true") == :ok
    end

    test "non-zero exit returns an error with the status" do
      assert {:error, m} = Editor.open("some/file", "false")
      assert m =~ "exited 1"
    end

    test "missing binary returns a not-found error" do
      assert {:error, m} = Editor.open("f", "definitely-not-an-editor-xyz")
      assert m =~ "editor not found: definitely-not-an-editor-xyz"
    end

    test "editor args are split and passed through" do
      assert {:error, m} = Editor.open("f", "sh -c 'exit 3'")
      assert m =~ "exited 3"
    end
  end
end
