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

  test "x on open task completes it and writes via io" do
    test_pid = self()

    io = %{
      fake_io()
      | write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end,
        append: fn _, _ -> :ok end
    }

    s = state([t("a", 1)], io: io)
    {s2, []} = Tui.update(:toggle_done, s)
    assert hd(s2.tasks).done
    assert_received {:write, "t", [%{done: true}]}
  end

  test "x on done task reopens; recur spawns next occurrence in the write" do
    test_pid = self()
    io = %{fake_io() | write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end}
    s = state([t("x 2026-09-20 a", 1)], io: io)
    {s2, _} = Tui.update(:toggle_done, s)
    refute hd(s2.tasks).done
    # Consume the reopen's write so the recur assertions see the next one.
    assert_received {:write, "t", _}

    s = state([t("r recur:1d due:2026-09-22", 1)], io: io)
    {_s2, _} = Tui.update(:toggle_done, s)
    assert_received {:write, "t", ts}
    assert List.last(ts).tags["due"] == "2026-09-23"
    assert List.last(ts).done == false
  end

  test "x with malformed recur toasts error, no write" do
    test_pid = self()
    io = %{fake_io() | write: fn _, _ -> send(test_pid, :wrote) && :ok end}
    s = state([t("r recur:bad", 1)], io: io)
    {s2, _} = Tui.update(:toggle_done, s)
    refute hd(s2.tasks).done
    assert s2.status =~ "invalid recur"
    refute_received :wrote
  end

  test "d opens confirm modal; m moves between files" do
    s = state([t("a", 1)])
    {s2, []} = Tui.update({:open_modal, :del}, s)
    assert s2.mode == :input and s2.modal.action == :del

    test_pid = self()

    io = %{
      fake_io()
      | append: fn p, _ts -> send(test_pid, {:append, p}) && :ok end,
        write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end
    }

    s = state([t("a", 1)], io: io)
    {s2, []} = Tui.update(:move, s)
    assert s2.tasks == []
    assert_received {:append, "d"}
    assert_received {:write, "t", []}
  end

  test "selection stays clamped after delete of last row" do
    s = state([t("a", 1), t("b", 2)], list_idx: 1)
    {s2, []} = Tui.update({:open_modal, :del}, s)
    {s3, []} = Tui.update({:dialog_result, :yes}, s2)
    assert s3.list_idx == 0 and length(s3.tasks) == 1
  end
end
