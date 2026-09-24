defmodule TodoTxt.Tui.View do
  @moduledoc "Render tree for the 3-pane layout + statusline + modals."

  import TermUI.Component.Helpers
  alias TermUI.Layout.Constraint
  alias TermUI.Renderer.Style
  alias TermUI.Widget.PickList
  alias TermUI.Widgets.{AlertDialog, TextInput}
  alias TodoTxt.Tui.State

  @sel Style.new(attrs: [:reverse])
  @dim Style.new(fg: :bright_black)
  @pri %{
    ?A => Style.new(fg: :red, attrs: [:bold]),
    ?B => Style.new(fg: :yellow),
    ?C => Style.new(fg: :cyan)
  }
  # Palette monochrome (state.plain) : attributs seuls, jamais de fg/bg.
  @dim_plain Style.new(attrs: [:dim])
  @pri_plain Style.new(attrs: [:bold])

  defp dim(%{plain: true}), do: @dim_plain
  defp dim(_), do: @dim

  defp pri(%{plain: true}, _p), do: @pri_plain
  defp pri(_, p), do: @pri[p]

  defp accent(%{plain: true}), do: nil
  defp accent(_), do: Style.new(fg: :cyan)

  def render(s) do
    stack(:vertical, [
      {body(s), Constraint.fill()},
      {statusline(s), Constraint.length(1)}
    ])
  end

  # Blocking modals replace the 3-pane body. AlertDialog.render/2 returns a
  # %{type: :overlay} plain map and PickList.render/2 a %RenderNode{cells:}
  # with absolute screen coordinates — both are valid stack children for
  # TermUI.Runtime.NodeRenderer (constrained child rendered into the body
  # rect, which spans the full width at the top of the screen).
  defp body(%{mode: :input, modal: %{widget_mod: mod, widget: w}} = s)
       when mod in [AlertDialog, PickList] do
    mod.render(w, %{width: s.width, height: s.height})
  end

  defp body(s) do
    stack(:horizontal, [
      {sidebar(s), Constraint.length(22)},
      {task_list(s), Constraint.fill()},
      {detail(s), Constraint.percentage(30) |> Constraint.with_min(24)}
    ])
  end

  defp sidebar(s) do
    entries = State.sidebar_entries(s)

    stack(
      :vertical,
      Enum.with_index(entries, fn
        {:header, label}, _ ->
          text(" " <> label, dim(s))

        {:all, label}, i ->
          item(s, i, label <> count_suffix(s))

        {kind, label, term}, i when kind in [:project, :context] ->
          mark = if term in s.filter_terms, do: "●", else: " "
          item(s, i, " #{mark} #{label}")

        {:view, label, _}, i ->
          item(s, i, "   " <> label)
      end)
    )
  end

  defp item(s, i, label) do
    style = if s.focus == :sidebar and s.sidebar_idx == i, do: @sel, else: nil
    text(label, style)
  end

  defp count_suffix(s) do
    c = State.counts(s)
    " (#{c.open}/#{c.done + c.open})"
  end

  defp task_list(s) do
    rows = State.rows(s)
    # ti = index parmi les {:task} seulement (list_idx réfère les tâches)
    stack(:vertical, render_rows(s, rows, 0))
  end

  defp render_rows(s, [], _ti), do: [text("  (vide)", dim(s))]

  defp render_rows(s, rows, ti) do
    {nodes, _ti} =
      Enum.map_reduce(rows, ti, fn
        {:header, label}, ti ->
          {text(" " <> label, Style.new(attrs: [:bold])), ti}

        {:task, t}, ti ->
          line = "#{t.line}: #{t.raw}"

          style =
            cond do
              s.focus == :list and s.list_idx == ti -> @sel
              t.done -> dim(s)
              Map.has_key?(@pri, t.priority) -> pri(s, t.priority)
              true -> nil
            end

          {text(" " <> line, style), ti + 1}
      end)

    nodes
  end

  defp detail(s) do
    case State.selected_task(s) do
      nil ->
        text("  —", dim(s))

      t ->
        fields = [
          {"Ligne", "#{t.line}"},
          {"Priorité", t.priority && <<t.priority>>},
          {"Créée", t.creation_date && Date.to_string(t.creation_date)},
          {"Faite", t.completion_date && Date.to_string(t.completion_date)},
          {"Due", t.tags["due"]},
          {"Seuil t:", t.tags["t"]},
          {"Recur", t.tags["recur"]},
          {"Projets", Enum.join(t.projects, " ")},
          {"Contextes", Enum.join(t.contexts, " ")}
        ]

        stack(
          :vertical,
          [text(" " <> t.raw, Style.new(attrs: [:bold])), text("")] ++
            for({k, v} <- fields, v not in [nil, ""], do: text("  #{k}: #{v}"))
        )
    end
  end

  # TextInput modals live inside the statusline: the 3-pane body stays
  # visible while the prompt + input take over the bottom line.
  defp statusline(%{mode: :input, modal: %{widget_mod: TextInput, widget: w, prompt: p}} = s) do
    stack(:horizontal, [
      text(" " <> p, accent(s)),
      TextInput.render(w, %{width: max(s.width - String.length(p) - 2, 10), height: 1})
    ])
  end

  defp statusline(s) do
    filters =
      if s.filter_terms == [], do: "", else: "  filter: #{Enum.join(s.filter_terms, " ")}"

    status = if s.status, do: "  │ #{s.status}", else: ""
    view = s.view |> Atom.to_string() |> String.upcase()

    text(
      " #{view}#{filters}#{status}  ·  a:add e:edit x:do d:del p:pri m:move /:filter E:$EDITOR ?:help q:quit",
      dim(s)
    )
  end
end
