defmodule TodoTxt.Tui.StateTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Parser, Tui.State}

  defp st(tasks, done \\ [], opts \\ []) do
    State.new(%{
      paths: %{todo: "t", done: "d", report: "r"},
      tasks: tasks,
      done_tasks: done,
      today: ~D[2026-09-21],
      io: fake_io(),
      caller: self()
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

  test "sidebar lists projects and contexts with counts, then views" do
    s = st([t("a +p1 @c1", 1), t("b +p1 @c2", 2), t("c +p2", 3)])
    entries = State.sidebar_entries(s)
    labels = Enum.map(entries, &elem(&1, 1))
    assert "── Projets ──" in labels and "── Contextes ──" in labels
    assert Enum.find(entries, &match?({:project, "+p1 (2)", "+p1"}, &1))
    assert Enum.find(entries, &match?({:context, "@c2 (1)", "@c2"}, &1))
    assert {:view, "Agenda", :agenda} in entries
    assert {:view, "Done", :done} in entries
  end

  test "rows in :todo are visible+filtered+sorted; done hidden by t:" do
    s = st([t("b", 2), t("(A) a", 1), t("hidden t:2999-01-01", 3)])
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [1, 2]
    s = %{s | filter_terms: ["b"]}
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [2]
  end

  test "rows in :done show done.txt newest last-appended first" do
    s = st([], [t("x old", 1), t("x new", 2)], view: :done)
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [2, 1]
  end

  test "rows in :agenda emit date headers and threshold section" do
    s = st([t("soon due:2026-09-25", 1), t("t t:2026-09-30", 2)], [], view: :agenda)
    rows = State.rows(s)
    assert {:header, "2026-09-25:"} in rows
    assert {:header, "THRESHOLDS:"} in rows
  end

  test "move_cursor clamps and skips headers" do
    s = st([t("a", 1), t("b", 2)])
    assert State.move_cursor(s, -1).list_idx == 0
    assert State.move_cursor(s, 5).list_idx == 1
  end

  test "activate_sidebar toggles project term; view entries switch view" do
    s = st([t("a +p", 1)])
    proj_idx = Enum.find_index(State.sidebar_entries(s), &match?({:project, _, _}, &1))
    s = %{s | sidebar_idx: proj_idx} |> State.activate_sidebar()
    assert s.filter_terms == ["+p"]
    s = State.activate_sidebar(s)
    assert s.filter_terms == []

    s = st([t("a", 1)])
    done_idx = Enum.find_index(State.sidebar_entries(s), &match?({:view, _, :done}, &1))
    s = %{s | sidebar_idx: done_idx} |> State.activate_sidebar()
    assert s.view == :done and s.list_idx == 0
  end

  test "selected_task follows list_idx over task rows" do
    s = st([t("a", 1), t("b", 2)], [], list_idx: 1)
    assert State.selected_task(s).line == 2
  end
end
