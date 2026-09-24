defmodule TodoTxt.TuiTest do
  use ExUnit.Case, async: true
  alias TermUI.Event
  alias TermUI.Widgets.TextInput
  alias TodoTxt.{Parser, Tui, Tui.State}

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

  test "x in done view reopens into todo.txt and rewrites done.txt" do
    test_pid = self()

    io = %{
      fake_io()
      | append: fn p, ts -> send(test_pid, {:append, p, ts}) && :ok end,
        write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end
    }

    s = state([t("a", 1)], io: io, view: :done, done_tasks: [t("x 2026-09-20 fini", 7)])
    {s2, []} = Tui.update(:toggle_done, s)
    assert s2.done_tasks == []
    assert s2.status =~ "reopened"
    # Append à todo.txt AVANT la réécriture de done.txt.
    assert_received {:append, "t", [reopened]}
    refute reopened.done
    assert_received {:write, "d", []}
    # todo.txt n'est jamais réécrit par cette mutation (pas de collision).
    refute_received {:write, "t", _}
  end

  test "del confirm on a task that vanished errors without writing" do
    test_pid = self()
    io = %{fake_io() | write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end}
    s = state([t("a", 1), t("b", 2)], io: io, list_idx: 1)
    {s2, []} = Tui.update({:open_modal, :del}, s)
    # La tâche a disparu entre l'ouverture du modal et la confirmation.
    s2 = %{s2 | tasks: [t("a", 1)]}
    {s3, []} = Tui.update({:dialog_result, :yes}, s2)
    assert s3.status =~ "no longer exists"
    assert s3.mode == :normal and s3.modal == nil
    refute_received {:write, _, _}
  end

  test "m in done view moves task back to todo.txt" do
    test_pid = self()

    io = %{
      fake_io()
      | append: fn p, _ts -> send(test_pid, {:append, p}) && :ok end,
        write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end,
        # Après le déplacement, done.txt ne contient plus que d1 : le reload
        # final relit les deux fichiers.
        read: fn
          "d" -> {:ok, [t("x 2026-09-19 d1", 5)]}
          _ -> {:ok, []}
        end
    }

    s =
      state([t("a", 1)],
        io: io,
        view: :done,
        done_tasks: [t("x 2026-09-19 d1", 5), t("x 2026-09-20 d2", 6)]
      )

    {s2, []} = Tui.update(:move, s)
    assert length(s2.done_tasks) == 1
    assert s2.status =~ "moved to todo"
    assert_received {:append, "t"}
    assert_received {:write, "d", [_]}
  end

  test "r reloads both files via io and refreshes mtimes" do
    io = %{
      read: fn
        "t" -> {:ok, [t("fresh open", 1)]}
        "d" -> {:ok, [t("x 2026-09-20 archived", 1)]}
      end,
      write: fn _, _ -> :ok end,
      append: fn _, _ -> :ok end,
      stat: fn _ -> {:ok, %{mtime: 42}} end
    }

    s = state([t("stale", 1)], io: io)
    {s2, []} = Tui.update(:reload, s)
    assert hd(s2.tasks).description == "fresh open"
    assert hd(s2.done_tasks).done
    assert s2.mtimes == %{todo: 42, done: 42}
  end

  test "a opens add modal; typing routes to TextInput; Enter submits" do
    test_pid = self()
    io = %{fake_io() | append: fn p, ts -> send(test_pid, {:append, p, ts}) && :ok end}
    s = state([t("x", 1)], io: io)

    {s2, []} = Tui.update({:open_modal, :add}, s)
    assert s2.mode == :input and s2.modal.action == :add

    {:msg, {:modal_event, ev}} = Tui.event_to_msg(Event.key("h"), s2)
    {s3, []} = Tui.update({:modal_event, ev}, s2)
    {:msg, {:modal_event, ev}} = Tui.event_to_msg(Event.key("i"), s3)
    {s4, []} = Tui.update({:modal_event, ev}, s3)
    assert TextInput.get_value(s4.modal.widget) == "hi"

    {s5, []} = Tui.update(:modal_submit, s4)
    assert s5.mode == :normal and s5.modal == nil
    assert_received {:append, "t", [%{description: "hi", line: 2}]}
  end

  test "Esc cancels modal without mutating" do
    s = state([t("a", 1)], mode: :input, modal: nil)
    {s2, []} = Tui.update({:open_modal, :edit}, s)
    {s3, []} = Tui.update(:modal_cancel, s2)
    assert s3.mode == :normal and s3.modal == nil
  end

  test "p opens PickList; {:select, item} sets priority" do
    s = state([t("a", 1)])
    {s2, []} = Tui.update({:open_modal, :pri}, s)
    assert s2.modal.action == :pri
    {s3, []} = Tui.update({:select, "B"}, s2)
    assert hd(s3.tasks).priority == ?B
  end

  test "dialog_result :yes deletes; :no closes" do
    s = state([t("a", 1)])
    {s2, []} = Tui.update({:open_modal, :del}, s)
    {s3, []} = Tui.update({:dialog_result, :no}, s2)
    assert s3.mode == :normal and length(s3.tasks) == 1
    {s4, []} = Tui.update({:open_modal, :del}, s3)
    {s5, []} = Tui.update({:dialog_result, :yes}, s4)
    assert s5.tasks == []
  end

  test "Ctrl+letter inside a TextInput modal does not insert text" do
    s = state([t("a", 1)])
    {s2, []} = Tui.update({:open_modal, :add}, s)
    ev = %Event.Key{key: "w", char: nil, modifiers: [:ctrl]}
    {s3, []} = Tui.update({:modal_event, ev}, s2)
    assert TextInput.get_value(s3.modal.widget) == ""
    assert s3.mode == :input and s3.modal.action == :add
  end

  test "submit on a task removed by an external reload fails cleanly (review focus 1)" do
    s = state([t("a", 1)])
    {s2, []} = Tui.update({:open_modal, :edit}, s)
    # Simule un reload externe : la ligne 1 n'existe plus.
    s3 = %{s2 | tasks: [Parser.parse("other", 7)], list_idx: 0}
    {s4, []} = Tui.update(:modal_submit, s3)
    assert s4.status =~ "error"
    assert Enum.map(s4.tasks, & &1.line) == [7]
  end

  test "tick reloads when mtime changed externally" do
    test_pid = self()
    old = {{2026, 1, 1}, {0, 0, 0}}
    new = {{2026, 1, 2}, {0, 0, 0}}

    io = %{
      fake_io()
      | stat: fn
          "t" -> {:ok, %{mtime: new}}
          _ -> {:error, :enoent}
        end,
        read: fn _ -> send(test_pid, :reread) && {:ok, []} end
    }

    s = state([], io: io)
    s = %{s | mtimes: %{todo: old, done: nil}}
    {s2, []} = Tui.update(:tick, s)
    assert_received :reread
    assert s2.mtimes.todo == new
    assert s2.status =~ "recharg"
  end

  test "tick is a no-op when mtimes unchanged" do
    m = {{2026, 1, 1}, {0, 0, 0}}

    io = %{
      fake_io()
      | stat: fn _ -> {:ok, %{mtime: m}} end,
        read: fn _ -> raise "must not read" end
    }

    s = %{state([], io: io) | mtimes: %{todo: m, done: m}}
    assert {^s, []} = Tui.update(:tick, s)
  end

  test "E sends {:tui_exit, :edit} to caller then quits" do
    s = state([])
    {_s, cmds} = Tui.update(:edit_external, s)
    assert_received {:tui_exit, :edit}
    assert TermUI.Command.quit() in cmds or :quit in cmds
  end

  # --- Régressions : resync cross-fichier + erreurs io (review) ---

  test "x in done view reloads both files: s.tasks picks up the reopened task" do
    test_pid = self()

    io = %{
      fake_io()
      | append: fn _, _ -> :ok end,
        write: fn _, _ -> :ok end,
        read: fn
          "t" -> send(test_pid, :reloaded_todo) && {:ok, [t("a", 1), t("fini", 8)]}
          "d" -> {:ok, []}
        end
    }

    s = state([t("a", 1)], io: io, view: :done, done_tasks: [t("x 2026-09-20 fini", 7)])
    {s2, []} = Tui.update(:toggle_done, s)
    assert_received :reloaded_todo
    assert Enum.map(s2.tasks, & &1.line) == [1, 8]
    assert s2.done_tasks == []
    assert s2.status =~ "reopened"
  end

  test "move to done then done-view delete: done.txt write keeps the moved task" do
    test_pid = self()
    moved = t("a", 1)
    survivor = t("x 2026-09-19 keep", 5)

    io = %{
      fake_io()
      | append: fn _, _ -> :ok end,
        write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end,
        read: fn
          "t" -> {:ok, []}
          "d" -> {:ok, [moved, survivor]}
        end
    }

    s = state([moved], io: io)
    {s2, []} = Tui.update(:move, s)
    assert_received {:write, "t", []}
    # Le reload post-move a resynchronisé done_tasks depuis done.txt.
    assert Enum.map(s2.done_tasks, & &1.line) == [1, 5]

    # Vue :done — tri desc par ligne : list_idx 0 sélectionne survivor (5).
    s3 = %{s2 | view: :done, list_idx: 0}
    {s4, []} = Tui.update({:open_modal, :del}, s3)
    {_s5, []} = Tui.update({:dialog_result, :yes}, s4)
    assert_received {:write, "d", remaining}
    assert Enum.map(remaining, & &1.line) == [1]
  end

  test "archive reloads done_tasks; a later done-view delete keeps archived tasks" do
    test_pid = self()
    done1 = t("x 2026-09-20 fini", 2)
    old = t("x 2026-09-19 ancien", 5)

    io = %{
      fake_io()
      | append: fn _, _ -> :ok end,
        write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end,
        read: fn
          "t" -> {:ok, [t("open", 1)]}
          "d" -> {:ok, [done1, old]}
        end
    }

    s = state([t("open", 1), done1], io: io)
    {s2, []} = Tui.update({:open_modal, :archive}, s)
    {s3, []} = Tui.update({:dialog_result, :yes}, s2)
    assert s3.status =~ "archived 1"
    assert_received {:write, "t", [%{line: 1}]}
    # done_tasks vient du reload, pas d'une mise à jour manuelle.
    assert Enum.map(s3.done_tasks, & &1.line) == [2, 5]

    # Supprimer `old` en vue :done (tri desc → list_idx 0 = ligne 5).
    s4 = %{s3 | view: :done, list_idx: 0}
    {s5, []} = Tui.update({:open_modal, :del}, s4)
    {_s6, []} = Tui.update({:dialog_result, :yes}, s5)
    assert_received {:write, "d", remaining}
    assert Enum.map(remaining, & &1.line) == [2]
  end

  test "relaunch after $EDITOR re-reads both files into env" do
    test_pid = self()
    old_editor = System.get_env("EDITOR")
    old_visual = System.get_env("VISUAL")
    System.delete_env("VISUAL")
    System.put_env("EDITOR", "true")

    runner = fn env ->
      send(test_pid, {:ran, env.tasks})
      :ok
    end

    io = %{
      fake_io()
      | read: fn _ -> {:ok, [t("post-edit", 9)]} end
    }

    env = %{
      paths: %{todo: "t", done: "d", report: "r"},
      tasks: [t("pre-edit", 1)],
      done_tasks: [],
      today: ~D[2026-09-21],
      io: io,
      runner: runner
    }

    try do
      send(self(), {:tui_exit, :edit})
      assert {:ok, nil} = Tui.run(env)
      assert_received {:ran, [%{description: "pre-edit"}]}
      # Le 2e run reçoit les listes relues après l'édition, pas l'env figé.
      assert_received {:ran, [%{description: "post-edit"}]}
    after
      if old_editor,
        do: System.put_env("EDITOR", old_editor),
        else: System.delete_env("EDITOR")

      if old_visual,
        do: System.put_env("VISUAL", old_visual),
        else: System.delete_env("VISUAL")
    end
  end

  test "io write error lands in status instead of crashing" do
    io = %{fake_io() | write: fn _, _ -> {:error, "disk full"} end}
    s = state([t("a", 1)], io: io)
    {s2, []} = Tui.update(:toggle_done, s)
    assert s2.status =~ "error"
    assert s2.status =~ "disk full"
  end

  test "failed append in move skips the remaining writes" do
    test_pid = self()

    io = %{
      fake_io()
      | append: fn _, _ -> {:error, "disk full"} end,
        write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end
    }

    s = state([t("a", 1)], io: io)
    {s2, []} = Tui.update(:move, s)
    assert s2.status =~ "error"
    assert s2.status =~ "disk full"
    refute_received {:write, _, _}
  end
end
