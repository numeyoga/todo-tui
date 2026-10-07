defmodule TodoTxt.Tui.ModalTest do
  use ExUnit.Case, async: true
  alias TodoTxt.Parser
  alias TodoTxt.Tui.{Modal, State}

  defp st(tasks, opts) do
    State.new(%{
      paths: %{todo: "t", done: "d", report: "r"},
      tasks: tasks,
      done_tasks: [],
      today: ~D[2026-09-21],
      caller: self(),
      io: %{
        read: fn _ -> {:ok, []} end,
        write: fn _, _ -> :ok end,
        append: fn _, _ -> :ok end,
        stat: fn _ -> {:error, :enoent} end
      }
    })
    |> struct!(opts)
  end

  defp t(raw, line), do: Parser.parse(raw, line)

  test "open(:add) creates TextInput with dynamic width exceeding legacy 60 limit" do
    s = st([t("a", 1)], width: 140)
    modal = Modal.open(:add, s)
    assert modal.action == :add
    assert modal.widget.width > 80
  end

  test "open(:edit) initializes TextInput with selected task raw content and dynamic width" do
    s = st([t("(A) buy milk @groceries", 1)], width: 120, list_idx: 0)
    modal = Modal.open(:edit, s)
    assert modal.action == :edit
    assert modal.line == 1
    assert modal.widget.width > 80
  end
end
