defmodule TodoTxt.TuiTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Parser, Tui, Tui.State}
  alias TermUI.Event

  defp state(tasks, opts \\ []) do
    State.new(%{
      paths: %{todo: "t", done: "d", report: "r"},
      tasks: tasks,
      done_tasks: [],
      today: ~D[2026-09-21],
      caller: self(),
      io: fake_io()
    })
    |> struct!(opts)
  end

  defp fake_io do
    %{
      read: fn _ -> {:ok, []} end,
      write: fn _, _ -> :ok end,
      append: fn _, _ -> :ok end,
      stat: fn _ -> {:error, :enoent} end
    }
  end

  defp t(raw, line), do: Parser.parse(raw, line)

  test "j/k move list cursor, arrows too" do
    s = state([t("a", 1), t("b", 2)])
    assert {:msg, {:nav, 1}} = Tui.event_to_msg(Event.key("j"), s)
    {s2, []} = Tui.update({:nav, 1}, s)
    assert s2.list_idx == 1
    {s3, []} = Tui.update({:nav, -1}, s2)
    assert s3.list_idx == 0
    assert {:msg, {:nav, 1}} = Tui.event_to_msg(Event.key(:down), s)
  end

  test "Tab toggles focus, Enter applies sidebar item" do
    s = state([t("a +p", 1)], focus: :sidebar)
    {s2, []} = Tui.update(:focus_next, s)
    assert s2.focus == :list
    {s3, []} = Tui.update(:focus_next, s2)
    assert s3.focus == :sidebar
  end

  test "q emits quit command" do
    s = state([])
    assert {:msg, :quit} = Tui.event_to_msg(Event.key("q"), s)
    {_s, cmds} = Tui.update(:quit, s)
    assert TermUI.Command.quit() in cmds or :quit in cmds
  end

  test "keys are ignored in :input mode except modal routing" do
    s = state([t("a", 1)], mode: :input, modal: %{action: :add, widget: nil})

    assert {:msg, {:modal_event, %Event.Key{key: "x"}}} =
             Tui.event_to_msg(Event.key("x"), s)
  end
end
