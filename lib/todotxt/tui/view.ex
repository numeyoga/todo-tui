defmodule TodoTxt.Tui.View do
  @moduledoc "Render tree for the 3-pane layout + statusline + modals."

  import TermUI.Component.Helpers
  alias TermUI.Component.RenderNode
  alias TermUI.Layout.Constraint
  alias TermUI.Renderer.Style
  alias TermUI.Widget.PickList
  alias TermUI.Widgets.{AlertDialog, TextInput}
  alias TodoTxt.Parser
  alias TodoTxt.Tui.State

  @sel Style.new(bg: :black, attrs: [:reverse])
  @sel_plain Style.new(attrs: [:reverse])
  @dim Style.new(fg: :bright_black)
  @pri %{
    ?A => Style.new(fg: :red, attrs: [:bold]),
    ?B => Style.new(fg: :yellow, attrs: [:bold]),
    ?C => Style.new(fg: :cyan),
    ?D => Style.new(fg: :green),
    ?E => Style.new(fg: :blue),
    ?F => Style.new(fg: :magenta)
  }
  # Palette monochrome (state.plain) : attributs seuls, jamais de fg/bg.
  @dim_plain Style.new(attrs: [:dim])

  defp dim(%{plain: true}), do: @dim_plain
  defp dim(_), do: @dim

  defp pri(_s, p), do: Map.get(@pri, p, Style.new(fg: :bright_black, attrs: [:bold]))

  defp accent(%{plain: true}), do: nil
  defp accent(_), do: Style.new(fg: :cyan)

  defp sel(%{plain: true}), do: @sel_plain
  defp sel(_), do: @sel

  defp status_style(%{plain: true}, _is_error), do: @dim_plain
  defp status_style(_, true), do: Style.new(fg: :red, attrs: [:bold])
  defp status_style(_, false), do: Style.new(fg: :green)

  def render(s) do
    stack(:vertical, [
      {header(s), Constraint.length(2)},
      {body(s), Constraint.fill()},
      {statusline(s), Constraint.length(3)}
    ])
  end

  defp header(s) do
    width = max(s.width, 40)
    title = " 📝 TodoTxt "
    scope = if s.local, do: "[LOCAL]", else: "[GLOBAL]"
    counts = State.counts(s)
    stats = "#{counts.open} ouvertes / #{counts.open + counts.done} total "
    date_str = Date.to_iso8601(s.today)

    left_part = title <> scope
    left_len = String.length(left_part)
    right_len = String.length(stats)
    center_part = "📅 " <> date_str
    center_len = String.length(center_part)

    pad1_len = max(1, div(width - left_len - right_len - center_len, 2))
    pad2_len = max(1, width - left_len - right_len - center_len - pad1_len)

    line1 =
      stack(:horizontal, [
        text(title, Style.new(fg: :cyan, attrs: [:bold])),
        text(scope, dim(s)),
        text(String.duplicate(" ", pad1_len), nil),
        text(center_part, Style.new(fg: :yellow, attrs: [:bold])),
        text(String.duplicate(" ", pad2_len), nil),
        text(stats, Style.new(fg: :green))
      ])

    line2 = text(build_top_separator(s), dim(s))

    stack(:vertical, [line1, line2])
  end

  defp build_top_separator(s) do
    width = max(s.width, 40)
    detail_w = max(round(s.width * 0.30), 24)
    sb_col = 20
    detail_col = max(width - detail_w, sb_col + 1)

    chars =
      for col <- 0..(width - 1) do
        cond do
          col == sb_col -> "┬"
          col == detail_col -> "┬"
          true -> "─"
        end
      end

    Enum.join(chars)
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

  defp body(%{mode: :input, modal: %{widget_mod: TextInput, action: :filter} = m} = s) do
    render_filter_modal(s, m)
  end

  defp body(%{mode: :input, modal: %{widget_mod: TextInput, action: a} = m} = s)
       when a in [:add, :edit, :append, :prepend] do
    render_input_modal(s, m)
  end

  defp body(s) do
    stack(:horizontal, [
      {sidebar(s), Constraint.length(21)},
      {task_list(s), Constraint.fill()},
      {detail(s), Constraint.percentage(30) |> Constraint.with_min(24)}
    ])
  end

  defp sidebar(s) do
    entries = State.sidebar_entries(s)
    avail_h = max(s.height - 5, 4)

    entry_nodes =
      Enum.with_index(entries, fn
        {:header, label}, _ ->
          padded = String.pad_trailing(" " <> label, 20)

          stack(:horizontal, [
            text(padded, Style.new(fg: :cyan, attrs: [:bold])),
            text("│", dim(s))
          ])

        {:all, label}, i ->
          item(s, i, label <> count_suffix(s))

        {kind, label, term}, i when kind in [:project, :context] ->
          mark = if term in s.filter_terms, do: "●", else: " "
          item(s, i, "#{mark} #{label}")

        {:view, label, _}, i ->
          item(s, i, "  " <> label)
      end)

    padding_count = max(0, avail_h - length(entries))

    padding_nodes =
      if padding_count > 0 do
        for _ <- 1..padding_count do
          stack(:horizontal, [text(String.pad_trailing("", 20), nil), text("│", dim(s))])
        end
      else
        []
      end

    stack(:vertical, entry_nodes ++ padding_nodes)
  end

  defp item(s, i, label) do
    padded = String.pad_trailing(" " <> label, 20)
    style = if s.focus == :sidebar and s.sidebar_idx == i, do: sel(s), else: nil

    stack(:horizontal, [
      text(padded, style),
      text("│", dim(s))
    ])
  end

  defp count_suffix(s) do
    c = State.counts(s)
    " (#{c.open}/#{c.done + c.open})"
  end

  defp task_list(s) do
    rows = State.rows(s)
    {vis_rows, initial_ti} = window_rows(s, rows)
    stack(:vertical, render_rows(s, vis_rows, initial_ti))
  end

  defp window_rows(s, rows) do
    avail = max(s.height - 5, 4)
    total = length(rows)

    if total <= avail do
      {rows, 0}
    else
      selected_row_idx = find_selected_row_index(rows, s.list_idx)

      start_offset =
        cond do
          selected_row_idx < avail -> 0
          selected_row_idx >= total - avail -> total - avail
          true -> selected_row_idx - div(avail, 2)
        end
        |> max(0)
        |> min(total - avail)

      visible = Enum.slice(rows, start_offset, avail)

      initial_ti =
        rows
        |> Enum.take(start_offset)
        |> Enum.count(&match?({:task, _}, &1))

      {visible, initial_ti}
    end
  end

  defp find_selected_row_index(rows, target_ti) do
    {_, idx} =
      Enum.reduce_while(rows, {0, 0}, fn
        {:task, _}, {^target_ti, row_idx} -> {:halt, {target_ti, row_idx}}
        {:task, _}, {ti, row_idx} -> {:cont, {ti + 1, row_idx + 1}}
        {:header, _}, {ti, row_idx} -> {:cont, {ti, row_idx + 1}}
      end)

    idx
  end

  defp render_rows(s, [], _ti), do: [text("  (vide)", dim(s))]

  defp render_rows(s, rows, ti) do
    detail_w = max(round(s.width * 0.30), 24)
    list_width = max(s.width - 21 - detail_w - 2, 20)

    {nodes, _ti} =
      Enum.map_reduce(rows, ti, fn
        {:header, label}, ti ->
          {text(" " <> label, Style.new(attrs: [:bold])), ti}

        {:task, t}, ti ->
          line = "#{t.line}: #{t.raw}"
          is_selected = s.focus == :list and s.list_idx == ti
          fit_line = fit_text(line, list_width - 1)

          node =
            cond do
              is_selected ->
                padded = String.pad_trailing(" " <> fit_line, list_width)
                text(padded, sel(s))

              t.done ->
                padded = String.pad_trailing(" " <> fit_line, list_width)
                text(padded, dim(s))

              true ->
                prefix = " #{t.line}: "
                raw_part = fit_text(t.raw, max(0, list_width - String.length(prefix) - 1))
                words = String.split(raw_part, " ", trim: false)
                colored_words = build_syntax_nodes(words, s)
                prefix_node = text(prefix, dim(s))
                used_len = String.length(prefix <> raw_part)
                pad_len = max(0, list_width - used_len)
                pad_node = text(String.duplicate(" ", pad_len), nil)

                stack(:horizontal, [prefix_node | colored_words] ++ [pad_node])
            end

          {node, ti + 1}
      end)

    nodes
  end

  defp fit_text(text, max_w) when is_binary(text) and max_w > 3 do
    if String.length(text) > max_w do
      String.slice(text, 0, max_w - 1) <> "…"
    else
      text
    end
  end

  defp fit_text(text, _max_w), do: text

  defp detail(s) do
    detail_w = max(round(s.width * 0.30), 24)
    content_w = max(detail_w - 4, 16)
    avail_h = max(s.height - 5, 4)

    nodes =
      case State.selected_task(s) do
        nil ->
          [text("│ —", dim(s))]

        t ->
          raw_lines = wrap_text(t.raw, content_w)
          header_nodes = Enum.map(raw_lines, &text("│ " <> &1, Style.new(attrs: [:bold])))

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

          field_nodes = Enum.flat_map(fields, fn {k, v} -> render_field(k, v, content_w) end)

          header_nodes ++ [text("│", dim(s)) | field_nodes]
      end

    padding_count = max(0, avail_h - length(nodes))

    padding_nodes =
      if padding_count > 0 do
        for _ <- 1..padding_count do
          text("│", dim(s))
        end
      else
        []
      end

    stack(:vertical, nodes ++ padding_nodes)
  end

  defp render_field(_k, v, _content_w) when v in [nil, ""], do: []

  defp render_field(k, v, content_w) do
    case wrap_text("#{k}: #{v}", content_w) do
      [] -> []
      [first | rest] -> [text("│   " <> first) | Enum.map(rest, &text("│     " <> &1))]
    end
  end

  defp wrap_text(nil, _width), do: []
  defp wrap_text("", _width), do: [""]

  defp wrap_text(text, max_width) when is_binary(text) and max_width > 0 do
    words = String.split(text, ~r/\s+/, trim: true)
    do_wrap(words, max_width, "", [])
  end

  defp do_wrap([], _max_width, current_line, acc) do
    if current_line == "", do: Enum.reverse(acc), else: Enum.reverse([current_line | acc])
  end

  defp do_wrap([word | rest], max_width, "", acc) do
    if String.length(word) > max_width do
      {head, tail} = String.split_at(word, max_width)
      do_wrap([tail | rest], max_width, "", [head | acc])
    else
      do_wrap(rest, max_width, word, acc)
    end
  end

  defp do_wrap([word | rest], max_width, current_line, acc) do
    combined = current_line <> " " <> word

    if String.length(combined) <= max_width do
      do_wrap(rest, max_width, combined, acc)
    else
      do_wrap([word | rest], max_width, "", [current_line | acc])
    end
  end

  defp render_filter_modal(s, modal) do
    modal_w = min(max(round(s.width * 0.65), 66), 84)
    inner_w = modal_w - 6
    inner_input_w = inner_w - 2
    title = "FILTRER LES TÂCHES [INS]"
    border_style = accent(s)

    top_border =
      "╭─ #{title} " <> String.duplicate("─", max(0, modal_w - String.length(title) - 5)) <> "╮"

    bot_border = "╰" <> String.duplicate("─", modal_w - 2) <> "╯"

    input_node =
      TextInput.render(%{modal.widget | width: inner_input_w}, %{
        width: inner_input_w,
        height: 1
      })
      |> fix_cursor_node(inner_input_w)

    modal_rows = [
      text(top_border, border_style),
      stack(:horizontal, [
        text("│", border_style),
        text(String.duplicate(" ", modal_w - 2), nil),
        text("│", border_style)
      ]),
      stack(:horizontal, [
        text("│  ", border_style),
        text("Mots-clés de recherche :", border_style),
        text(String.duplicate(" ", max(0, inner_w - 24)), nil),
        text("  │", border_style)
      ]),
      stack(:horizontal, [
        text("│  > ", border_style),
        input_node,
        text("  │", border_style)
      ]),
      stack(:horizontal, [
        text("│", border_style),
        text(String.duplicate(" ", modal_w - 2), nil),
        text("│", border_style)
      ]),
      stack(:horizontal, [
        text("│  ", border_style),
        text("Filtres disponibles (ET logique) :", border_style),
        text(String.duplicate(" ", max(0, inner_w - 34)), nil),
        text("  │", border_style)
      ]),
      stack(:horizontal, [
        text("│  ", border_style),
        text("  • +projet      Filtre par projet exact", Style.new(fg: :cyan)),
        text(String.duplicate(" ", max(0, inner_w - 40)), nil),
        text("  │", border_style)
      ]),
      stack(:horizontal, [
        text("│  ", border_style),
        text("  • @contexte    Filtre par contexte exact", Style.new(fg: :magenta)),
        text(String.duplicate(" ", max(0, inner_w - 42)), nil),
        text("  │", border_style)
      ]),
      stack(:horizontal, [
        text("│  ", border_style),
        text("  • texte        Recherche insensible à la casse", dim(s)),
        text(String.duplicate(" ", max(0, inner_w - 48)), nil),
        text("  │", border_style)
      ]),
      stack(:horizontal, [
        text("│", border_style),
        text(String.duplicate(" ", modal_w - 2), nil),
        text("│", border_style)
      ]),
      stack(:horizontal, [
        text("│  ", border_style),
        text("[Ctrl+U] Vider le champ   [Entrée] Filtrer   [Échap] Annuler", dim(s)),
        text(String.duplicate(" ", max(0, inner_w - 60)), nil),
        text("  │", border_style)
      ]),
      text(bot_border, border_style)
    ]

    box_h = length(modal_rows)
    top_pad = max(div(max(s.height - 5, 4) - box_h, 2), 0)
    left_pad = max(div(s.width - modal_w, 2), 1)

    padded_box =
      Enum.map(modal_rows, fn row ->
        stack(:horizontal, [
          text(String.duplicate(" ", left_pad), nil),
          row
        ])
      end)

    stack(:vertical, List.duplicate(text("", nil), top_pad) ++ padded_box)
  end

  defp render_input_modal(s, modal) do
    modal_w = min(max(round(s.width * 0.70), 56), 96)
    inner_w = modal_w - 6
    inner_input_w = inner_w - 2
    border_style = accent(s)
    title = action_title(modal.action, modal) <> " [INS]"

    top_border =
      "╭─ #{title} " <> String.duplicate("─", max(0, modal_w - String.length(title) - 5)) <> "╮"

    bot_border = "╰" <> String.duplicate("─", modal_w - 2) <> "╯"

    val = TextInput.get_value(modal.widget)
    task = Parser.parse(val, 1)

    preview_lines = wrap_text(val, inner_w)
    preview_lines = if preview_lines == [], do: [""], else: preview_lines

    preview_row_nodes =
      Enum.map(preview_lines, fn line ->
        words = String.split(line, " ", trim: false)
        line_nodes = build_syntax_nodes(words, s)
        pad = max(0, inner_w - String.length(line))

        stack(:horizontal, [
          text("│  ", border_style),
          stack(:horizontal, line_nodes),
          text(String.duplicate(" ", pad), nil),
          text("  │", border_style)
        ])
      end)

    tags = []
    tags = if task.priority, do: ["Prio [#{<<task.priority>>}]" | tags], else: tags
    tags = if task.projects != [], do: [Enum.join(task.projects, " ") | tags], else: tags
    tags = if task.contexts != [], do: [Enum.join(task.contexts, " ") | tags], else: tags

    tags =
      if Map.has_key?(task.tags, "due"), do: ["Échéance: #{task.tags["due"]}" | tags], else: tags

    tags_summary = Enum.reverse(tags) |> Enum.join("  ·  ")

    legend_nodes = [
      text("│  ", border_style),
      text("Syntaxe : ", dim(s)),
      text("+projet", Style.new(fg: :cyan, attrs: [:bold])),
      text("  ", nil),
      text("@contexte", Style.new(fg: :magenta, attrs: [:bold])),
      text("  ", nil),
      text("(A)", pri(s, ?A)),
      text("  ", nil),
      text("due:AAAA-MM-JJ", Style.new(fg: :yellow, attrs: [:bold])),
      text(String.duplicate(" ", max(0, inner_w - 49)), nil),
      text("  │", border_style)
    ]

    input_node =
      TextInput.render(%{modal.widget | width: inner_input_w}, %{
        width: inner_input_w,
        height: 1
      })
      |> fix_cursor_node(inner_input_w)

    modal_rows =
      [
        text(top_border, border_style),
        stack(:horizontal, [
          text("│", border_style),
          text(String.duplicate(" ", modal_w - 2), nil),
          text("│", border_style)
        ]),
        stack(:horizontal, [
          text("│  ", border_style),
          text("Saisie :", border_style),
          text(String.duplicate(" ", max(0, inner_w - 8)), nil),
          text("  │", border_style)
        ]),
        stack(:horizontal, [
          text("│  > ", border_style),
          input_node,
          text("  │", border_style)
        ]),
        stack(:horizontal, legend_nodes),
        stack(:horizontal, [
          text("│", border_style),
          text(String.duplicate(" ", modal_w - 2), nil),
          text("│", border_style)
        ]),
        stack(:horizontal, [
          text("│  ", border_style),
          text("Aperçu en direct :", border_style),
          text(String.duplicate(" ", max(0, inner_w - 18)), nil),
          text("  │", border_style)
        ])
      ] ++
        preview_row_nodes ++
        [
          if tags_summary != "" do
            badge = fit_text(tags_summary, inner_w)

            stack(:horizontal, [
              text("│  ", border_style),
              text(badge, Style.new(fg: :green)),
              text(String.duplicate(" ", max(0, inner_w - String.length(badge))), nil),
              text("  │", border_style)
            ])
          else
            stack(:horizontal, [
              text("│", border_style),
              text(String.duplicate(" ", modal_w - 2), nil),
              text("│", border_style)
            ])
          end,
          stack(:horizontal, [
            text("│", border_style),
            text(String.duplicate(" ", modal_w - 2), nil),
            text("│", border_style)
          ]),
          stack(:horizontal, [
            text("│  ", border_style),
            text("[Entrée] Valider    [Échap] Annuler", dim(s)),
            text(String.duplicate(" ", max(0, inner_w - 35)), nil),
            text("  │", border_style)
          ]),
          text(bot_border, border_style)
        ]

    box_h = length(modal_rows)
    top_pad = max(div(max(s.height - 5, 4) - box_h, 2), 0)
    left_pad = max(div(s.width - modal_w, 2), 1)

    padded_box =
      Enum.map(modal_rows, fn row ->
        stack(:horizontal, [
          text(String.duplicate(" ", left_pad), nil),
          row
        ])
      end)

    stack(:vertical, List.duplicate(text("", nil), top_pad) ++ padded_box)
  end

  defp fix_cursor_node(node, target_w) do
    do_fix_cursor_node(node, target_w)
  end

  defp do_fix_cursor_node(
         %RenderNode{type: :stack, direction: :horizontal, children: [b, c, a]} = parent,
         target_w
       ) do
    b_len = String.length(b.content || "")
    c_len = String.length(c.content || "")
    a_len = String.length(a.content || "")
    total = b_len + c_len + a_len

    b_trimmed =
      if is_integer(target_w) and total > target_w and b_len > 0 do
        %{b | content: String.slice(b.content, 0, b_len - (total - target_w))}
      else
        b
      end

    new_children = Enum.map([b_trimmed, c, a], &do_fix_cursor_node(&1, nil))
    %{parent | children: new_children}
  end

  defp do_fix_cursor_node(%RenderNode{children: children} = node, target_w)
       when is_list(children) do
    %{node | children: Enum.map(children, &do_fix_cursor_node(&1, target_w))}
  end

  defp do_fix_cursor_node(
         %RenderNode{type: :text, content: content, style: %Style{attrs: attrs} = st} = node,
         _target_w
       ) do
    if :reverse in attrs do
      char = if content in [" ", ""], do: "█", else: content

      %{
        node
        | content: char,
          style: %Style{st | fg: :cyan, bg: :black, attrs: MapSet.new([:reverse, :bold])}
      }
    else
      node
    end
  end

  defp do_fix_cursor_node(node, _target_w), do: node

  defp action_title(:add, _m), do: "NOUVELLE TÂCHE"
  defp action_title(:edit, m), do: "MODIFIER LA TÂCHE ##{m[:line]}"
  defp action_title(:append, m), do: "AJOUTER À LA FIN ##{m[:line]}"
  defp action_title(:prepend, m), do: "AJOUTER AU DÉBUT ##{m[:line]}"
  defp action_title(a, _m), do: a |> Atom.to_string() |> String.upcase()

  defp build_syntax_nodes(words, s) do
    Enum.flat_map(Enum.with_index(words), fn {w, i} ->
      prefix = if i > 0, do: [text(" ", nil)], else: []
      prefix ++ [text(w, word_style(w, s))]
    end)
  end

  defp word_style(w, %{plain: true}) do
    if String.match?(w, ~r/^\([A-Z]\)$/) or String.starts_with?(w, "+") or
         String.starts_with?(w, "@"),
       do: Style.new(attrs: [:bold]),
       else: nil
  end

  defp word_style(w, s) do
    cond do
      String.match?(w, ~r/^\([A-Z]\)$/) ->
        pri(s, :binary.first(String.slice(w, 1, 1)))

      String.starts_with?(w, "+") ->
        Style.new(fg: :cyan, attrs: [:bold])

      String.starts_with?(w, "@") ->
        Style.new(fg: :magenta, attrs: [:bold])

      String.starts_with?(w, "due:") ->
        Style.new(fg: :yellow, attrs: [:bold])

      String.starts_with?(w, "t:") ->
        Style.new(fg: :blue, attrs: [:bold])

      String.contains?(w, ":") ->
        Style.new(fg: :yellow)

      String.match?(w, ~r/^\d{4}-\d{2}-\d{2}$/) ->
        Style.new(fg: :bright_black)

      true ->
        nil
    end
  end

  defp statusline(%{mode: :input, modal: %{widget_mod: TextInput, action: a}} = s)
       when a in [:add, :edit, :append, :prepend] do
    sep = text(build_separator(s), dim(s))
    action_label = action_title(a, s.modal)
    scope = if s.local, do: "[LOCAL]", else: "[GLOBAL]"
    line1 = text(" #{action_label} #{scope}", accent(s))
    line2 = text(" [Entrée] Valider    [Échap] Annuler", dim(s))

    stack(:vertical, [sep, line1, line2])
  end

  defp statusline(%{mode: :input, modal: %{widget_mod: TextInput, widget: w, prompt: p}} = s) do
    input_width = max(s.width - String.length(p) - 2, 10)
    sep = text(build_separator(s), dim(s))

    stack(:vertical, [
      sep,
      stack(:horizontal, [
        text(" " <> p, accent(s)),
        TextInput.render(w, %{width: input_width, height: 1})
      ]),
      text(" Entrée: valider  ·  Échap: annuler", dim(s))
    ])
  end

  defp statusline(s) do
    filters =
      if s.filter_terms == [], do: "", else: "  filter: #{Enum.join(s.filter_terms, " ")}"

    status = if s.status, do: "  │ #{s.status}", else: ""
    view = s.view |> Atom.to_string() |> String.upcase()
    scope = if s.local, do: "[LOCAL]", else: "[GLOBAL]"
    is_error = s.status != nil and String.starts_with?(s.status, "error")

    sep = text(build_separator(s), dim(s))
    line1 = text(" #{view} #{scope}#{filters}#{status}", status_style(s, is_error))
    line2 = text(shortcuts_text(s), dim(s))

    stack(:vertical, [sep, line1, line2])
  end

  defp build_separator(s) do
    width = max(s.width, 40)
    detail_w = max(round(s.width * 0.30), 24)
    sb_col = 20
    detail_col = max(width - detail_w, sb_col + 1)

    chars =
      for col <- 0..(width - 1) do
        cond do
          col == sb_col -> "┴"
          col == detail_col -> "┴"
          true -> "─"
        end
      end

    Enum.join(chars)
  end

  defp shortcuts_text(%{focus: :sidebar} = s) do
    if is_integer(s.width) and s.width < 100 do
      " Tab/l:Tâches  j/k:Nav  Entrée:Filtrer  /:Filtre  ?:Aide  q:Quitter"
    else
      " Tab/l: Liste des tâches   j/k: Naviguer   Entrée: Filtrer / Sélectionner   /: Filtrer   ?: Aide   q: Quitter"
    end
  end

  defp shortcuts_text(s) do
    selected = State.selected_task(s)
    is_done = s.view == :done or (selected != nil and selected.done)

    {x_label, m_label} =
      if is_done do
        {"x:Recommencer", "m:Recommencer"}
      else
        {"x:Terminer", "m:Terminer"}
      end

    if is_integer(s.width) and s.width < 100 do
      " a:Ajouter  e:Modifier  #{x_label}  d:Supprimer  p:Priorité  #{m_label}  Tab/h:Menu  /:Filtrer  ?:Aide  q:Quitter"
    else
      " a: Ajouter  e: Modifier  #{x_label}  d: Supprimer  p: Priorité  #{m_label}  L: Scope  Tab/h: Menu  /: Filtrer  E: Éditeur  ?: Aide  q: Quitter"
    end
  end
end
