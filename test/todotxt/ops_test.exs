defmodule TodoTxt.OpsTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Ops, Parser}

  defp t(raw, line), do: Parser.parse(raw, line)
  @today ~D[2026-09-21]

  test "add assigns max+1 line and inserts creation date" do
    tasks = [t("a", 1), t("b", 5)]
    new = Ops.add(tasks, "call mom +fam", @today)
    assert new.line == 6
    assert new.raw == "2026-09-21 call mom +fam"
    assert new.creation_date == @today
  end

  test "add keeps (A) priority before the date" do
    new = Ops.add([], "(A) urgent", @today)
    assert new.raw == "(A) 2026-09-21 urgent"
  end

  test "complete marks done, drops priority, returns no recur" do
    tasks = [t("(A) 2026-09-01 x +p", 3)]
    assert {:ok, [done], nil} = Ops.complete(tasks, hd(tasks), @today)
    assert done.done and done.completion_date == @today and done.priority == nil
  end

  test "complete spawns next recurrence with line max+1" do
    tasks = [t("pay rent +home due:2026-09-30 recur:1m", 2), t("other", 9)]
    assert {:ok, _tasks, recur} = Ops.complete(tasks, hd(tasks), @today)
    assert recur.tags["due"] == "2026-10-30"
    assert recur.done == false
  end

  test "complete with malformed recur errors before mutating" do
    tasks = [t("x recur:banana", 1)]
    assert {:error, msg} = Ops.complete(tasks, hd(tasks), @today)
    assert msg =~ "invalid recur"
  end

  test "uncomplete clears done and completion date" do
    tasks = [t("x 2026-09-20 done thing", 4)]
    assert {:ok, [t2]} = Ops.uncomplete(tasks, hd(tasks))
    refute t2.done
    assert t2.completion_date == nil
  end

  test "delete removes the task; delete_term strips the token" do
    tasks = [t("a +p @c", 1), t("b", 2)]
    assert {:ok, [left]} = Ops.delete(tasks, hd(tasks))
    assert left.line == 2
    assert {:ok, [stripped, _]} = Ops.delete_term(tasks, hd(tasks), "+p")
    assert stripped.description == "a @c"
  end

  test "set_priority validates A-Z and rejects done tasks" do
    t1 = t("open", 1)
    assert {:ok, [p]} = Ops.set_priority([t1], t1, ?B)
    assert p.priority == ?B
    assert {:error, _} = Ops.set_priority([t1], t1, ?a)
    done = t("x done", 2)
    assert {:error, msg} = Ops.set_priority([done], done, ?A)
    assert msg =~ "already done"
  end

  test "replace_text reparses the full line" do
    tasks = [t("old", 7)]
    assert {:ok, [new]} = Ops.replace_text(tasks, hd(tasks), "(C) 2026-01-01 new +proj")
    assert new.line == 7 and new.priority == ?C and "+proj" in new.projects
  end

  test "append_text and prepend_text" do
    tasks = [t("base @c", 1)]
    assert {:ok, [a]} = Ops.append_text(tasks, hd(tasks), "tail due:2026-10-01")
    assert a.description =~ "tail due:2026-10-01"
    assert {:ok, [p]} = Ops.prepend_text(tasks, hd(tasks), "head")
    assert p.description =~ ~r/^head base/
  end

  test "archive splits done; dedupe keeps first occurrence" do
    tasks = [t("x done1", 1), t("open", 2), t("open", 3)]
    assert {open, done} = Ops.archive(tasks)
    assert Enum.map(open, & &1.line) == [2, 3]
    assert length(done) == 1
    assert Enum.map(Ops.dedupe(tasks), & &1.line) == [1, 2]
  end

  test "agenda groups open tasks by due date within 14 days + thresholds" do
    tasks = [
      t("overdue due:2026-09-01", 1),
      t("soon due:2026-09-25", 2),
      t("far due:2027-01-01", 3),
      t("x done due:2026-09-22", 4),
      t("hidden t:2026-09-30", 5)
    ]

    {groups, thresholds} = Ops.agenda(tasks, @today)

    assert Enum.map(groups, fn {d, ts} -> {d, Enum.map(ts, & &1.line)} end) ==
             [{~D[2026-09-25], [2]}]

    assert Enum.map(thresholds, & &1.line) == [5]
  end
end
