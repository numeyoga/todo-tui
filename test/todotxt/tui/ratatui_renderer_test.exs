defmodule TodoTxt.Tui.RatatuiRendererTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias TodoTxt.Task
  alias TodoTxt.Tui.{RatatuiRenderer, State}

  test "renders detail pane with task details and separator" do
    tasks = [
      %Task{
        line: 1,
        raw: "(A) Buy milk +groceries @store due:2026-10-10",
        description: "Buy milk",
        priority: ?A,
        projects: ["groceries"],
        contexts: ["store"],
        tags: %{"due" => "2026-10-10"}
      }
    ]

    state = State.new(%{tasks: tasks, width: 80, height: 24, plain: false, today: ~D[2026-10-07]})
    frame = %{width: 80, height: 24}

    widgets = RatatuiRenderer.render(state, frame)

    # Detail widget is positioned at x=56, width=24
    detail_widget =
      Enum.find_value(widgets, fn
        {w, %Rect{x: 56, width: 24}} -> w
        _ -> nil
      end)

    assert detail_widget != nil
    assert detail_widget.text != []

    rendered_lines =
      Enum.map(detail_widget.text, fn line ->
        Enum.map_join(line.spans, "", & &1.content)
      end)

    assert Enum.any?(rendered_lines, &String.contains?(&1, "Buy milk"))
    assert Enum.any?(rendered_lines, &String.contains?(&1, "Ligne: 1"))
    assert Enum.any?(rendered_lines, &String.contains?(&1, "Priorité: A"))
    assert Enum.any?(rendered_lines, &String.contains?(&1, "Due: 2026-10-10"))
    assert Enum.any?(rendered_lines, &String.contains?(&1, "Projets: groceries"))
    assert Enum.any?(rendered_lines, &String.contains?(&1, "Contextes: store"))

    # Every rendered line starts with the vertical separator "│"
    assert Enum.all?(rendered_lines, &String.starts_with?(&1, "│"))
  end

  test "renders custom tags (id, note, min, count) in ratatui detail pane" do
    tasks = [
      %Task{
        line: 1,
        raw: "Review doc id:101 note:spec.md min:30 count:2",
        description: "Review doc",
        tags: %{"id" => "101", "note" => "spec.md", "min" => "30", "count" => "2"}
      }
    ]

    state = State.new(%{tasks: tasks, width: 80, height: 24, plain: false, today: ~D[2026-10-07]})
    frame = %{width: 80, height: 24}

    widgets = RatatuiRenderer.render(state, frame)

    detail_widget =
      Enum.find_value(widgets, fn
        {w, %Rect{x: 56, width: 24}} -> w
        _ -> nil
      end)

    assert detail_widget != nil

    rendered_lines =
      Enum.map(detail_widget.text, fn line ->
        Enum.map_join(line.spans, "", & &1.content)
      end)

    assert Enum.any?(rendered_lines, &String.contains?(&1, "ID: 101"))
    assert Enum.any?(rendered_lines, &String.contains?(&1, "Note: spec.md"))
    assert Enum.any?(rendered_lines, &String.contains?(&1, "Temps min: 30"))
    assert Enum.any?(rendered_lines, &String.contains?(&1, "Compteur: 2"))
  end

  test "renders detail pane with placeholder when no task is selected" do
    state = State.new(%{tasks: [], width: 80, height: 24, plain: false, today: ~D[2026-10-07]})
    frame = %{width: 80, height: 24}

    widgets = RatatuiRenderer.render(state, frame)

    detail_widget =
      Enum.find_value(widgets, fn
        {w, %Rect{x: 56, width: 24}} -> w
        _ -> nil
      end)

    assert detail_widget != nil

    rendered_lines =
      Enum.map(detail_widget.text, fn line ->
        Enum.map_join(line.spans, "", & &1.content)
      end)

    assert Enum.any?(rendered_lines, &String.contains?(&1, "—"))
    assert Enum.all?(rendered_lines, &String.starts_with?(&1, "│"))
  end

  test "renders Clear widget covering the frame when redraw_clearing is true" do
    state = %{State.new(%{tasks: [], width: 80, height: 24}) | redraw_clearing: true}
    frame = %{width: 80, height: 24}

    widgets = RatatuiRenderer.render(state, frame)
    assert [{%ExRatatui.Widgets.Clear{}, %Rect{x: 0, y: 0, width: 80, height: 24}}] = widgets
  end
end
