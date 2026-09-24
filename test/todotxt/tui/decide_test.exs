defmodule TodoTxt.Tui.DecideTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Parser, Tui, Tui.State}

  # decide/2 must never touch io: every io function raises.
  defp state(tasks, opts \\ []) do
    boom = fn _ -> raise "io in decide/2" end
    boom2 = fn _, _ -> raise "io in decide/2" end

    State.new(%{
      paths: %{todo: "t", done: "d"},
      tasks: tasks,
      done_tasks: [],
      today: ~D[2026-09-21],
      caller: self(),
      io: %{read: boom, write: boom2, append: boom2, stat: boom}
    })
    |> struct!(opts)
  end

  defp t(raw, line), do: Parser.parse(raw, line)

  test "mutations become io effects, not io calls" do
    s = state([t("a", 1)])
    task = hd(s.tasks)

    assert {^s, [{:persist, :complete, %{task: ^task}}, :sync]} = Tui.decide(:toggle_done, s)
    assert {^s, [{:persist, :move, %{from: :todo}}, :reload]} = Tui.decide(:move, s)
    assert {^s, [:reload]} = Tui.decide(:reload, s)
    assert {^s, [:watch]} = Tui.decide(:tick, s)
  end

  test "archive / delete dialogs emit persist effects" do
    s = state([t("a", 1)], modal: %{action: :archive}, mode: :input)
    assert {_, [{:persist, :archive, _}, :reload]} = Tui.decide({:dialog_result, :yes}, s)

    s = state([t("a", 1)], modal: %{action: :del, line: 1}, mode: :input)

    assert {_, [{:persist, :edit, %{op: :delete, list: :todo}}, :sync]} =
             Tui.decide({:dialog_result, :yes}, s)
  end

  test "edit_external emits the caller notification before quit" do
    s = state([])
    assert {^s, [{:send, pid, {:tui_exit, :edit}}, quit]} = Tui.decide(:edit_external, s)
    assert pid == self() and quit == TermUI.Command.quit()
    refute_received {:tui_exit, :edit}
  end
end
