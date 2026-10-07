defmodule TodoTxt.Tui.View do
  @moduledoc "Render tree for the 3-pane layout + statusline + modals."

  import TermUI.Component.Helpers
  alias TermUI.Component.RenderNode
  alias TermUI.Layout.Constraint
  alias TermUI.Renderer.Style
  alias TermUI.Widget.PickList
  alias TermUI.Widgets.{AlertDialog, TextInput}
  alias TodoTxt.{Dependencies, Parser, Task, TimeTracker}
  alias TodoTxt.Tui.State

  @sel Style.new(bg: :black, attrs: [:reverse])
  @sel_plain Style.new(attrs: [:reverse])
  @dim Style.new(fg: :bright_black)
  @pri %{
    ?A => Style.new(fg: :red, attrs: [:bold]),
    ?B => Style.new(fg: :yellow, attrs: [:bold]),
    ?C => Style.new(fg: :cyan, attrs: [:bold]),
    ?D => Style.new(fg: :green, attrs: [:bold]),
    ?E => Style.new(fg: :blue, attrs: [:bold]),
    ?F => Style.new(fg: :magenta, attrs: [:bold])
  }
  # Palette monochrome (state.plain) : attributs seuls, jamais de fg/bg.
  @dim_plain Style.new(attrs: [:dim])

  defp dim(%{plain: true}), do: @dim_plain
  defp dim(_), do: @dim

  defp pri(%{plain: true}, _p), do: Style.new(attrs: [:bold])
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
      {statusline(s), Constraint.length(statusline_height(s))}
    ])
  end

  defp body_height(s) do
    max(Map.get(s, :height, 24) - 2 - statusline_height(s), 1)
  end

  defp header(s) do
    width = max(s.width, 1)
    title = " 📝 TodoTxt "
    scope = if s.local, do: "[LOCAL]", else: "[GLOBAL]"
    counts = State.counts(s)
    stats_text = "#{counts.open} ouvertes / #{counts.open + counts.done} total "
    datetime_str = "📅 " <> current_date_str(s) <> " " <> current_time_str(s)

    {center_part, stats} =
      cond do
        width >= 75 -> {datetime_str, stats_text}
        width >= 50 -> {"", stats_text}
        true -> {"", ""}
      end

    left_part = title <> scope
    left_len = String.length(left_part)
    right_len = String.length(stats)
    center_len = String.length(center_part)

    rem_pad = max(0, width - left_len - right_len - center_len)
    pad1_len = div(rem_pad, 2)
    pad2_len = rem_pad - pad1_len

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

  defp current_date_str(s) do
    case Map.get(s, :today) do
      %Date{} = d ->
        Date.to_iso8601(d)

      d when is_binary(d) ->
        d

      nil ->
        case Map.get(s, :now) do
          %DateTime{} = dt -> Date.to_iso8601(DateTime.to_date(dt))
          %NaiveDateTime{} = ndt -> Date.to_iso8601(NaiveDateTime.to_date(ndt))
          _ -> Date.to_iso8601(Date.utc_today())
        end
    end
  end

  defp current_time_str(s) do
    case Map.get(s, :now) do
      nil ->
        Calendar.strftime(NaiveDateTime.local_now(), "%H:%M")

      %Time{} = t ->
        Calendar.strftime(t, "%H:%M")

      %NaiveDateTime{} = ndt ->
        Calendar.strftime(ndt, "%H:%M")

      %DateTime{} = dt ->
        Calendar.strftime(dt, "%H:%M")

      str when is_binary(str) ->
        str
    end
  end

  defp build_top_separator(s) do
    width = max(s.width, 1)
    detail_w = max(round(width * 0.30), 24)
    sb_col = 20
    detail_col = max(width - detail_w, sb_col + 1)

    chars =
      for col <- 0..(width - 1) do
        cond do
          col == sb_col and col < width - 1 -> "┬"
          col == detail_col and col < width - 1 -> "┬"
          true -> "─"
        end
      end

    Enum.join(chars)
  end

  # Blocking modals replace the 3-pane body. AlertDialog.render/2 returns a
  # %{type: :overlay} plain map and PickList.render/2 a %RenderNode{cells:}
  # with absolute screen coordinates — both are valid stack children for
  # TermUI.Runtime.NodeRenderer (constrained child rendered into the body
  defp body(%{mode: :input, modal: %{action: :help} = m} = s) do
    render_help_modal(s, m)
  end

  defp body(%{mode: :input, modal: %{action: a} = m} = s) when a in [:del, :archive] do
    render_confirm_modal(s, m)
  end

  defp body(%{mode: :input, modal: %{widget_mod: AlertDialog, widget: w}} = s) do
    AlertDialog.render(w, %{width: s.width, height: s.height})
  end

  defp body(%{mode: :input, modal: %{action: :pri} = m} = s) do
    render_priority_modal(s, m)
  end

  defp body(%{mode: :input, modal: %{widget_mod: PickList, widget: w}} = s) do
    PickList.render(w, %{width: s.width, height: s.height})
  end

  defp body(%{mode: :input, modal: %{widget_mod: TextInput, action: :filter} = m} = s) do
    render_filter_modal(s, m)
  end

  defp body(%{mode: :input, modal: %{widget_mod: TextInput, action: :tag} = m} = s) do
    render_tag_modal(s, m)
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
    avail_h = body_height(s)

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
    list_width = max(s.width - 21 - detail_w, 20)

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
    content_w = max(detail_w - 3, 16)
    avail_h = body_height(s)

    sep_column =
      stack(:vertical, for(_ <- 1..avail_h, do: text("│", dim(s))))

    content_column = detail_content(s, content_w, avail_h)

    stack(:horizontal, [
      {sep_column, Constraint.length(1)},
      {content_column, Constraint.fill()}
    ])
  end

  defp detail_content(s, content_w, avail_h) do
    nodes =
      case State.selected_task(s) do
        nil -> [text("  —", dim(s))]
        t -> build_task_detail_nodes(t, s, content_w)
      end

    padding_count = max(0, avail_h - length(nodes))

    padding_nodes =
      if padding_count > 0 do
        for _ <- 1..padding_count, do: text("", nil)
      else
        []
      end

    stack(:vertical, nodes ++ padding_nodes)
  end

  defp render_field(_k, v, _st, _content_w, _s) when v in [nil, ""], do: []

  defp render_field(k, v, st, content_w, s) do
    val_style =
      cond do
        s.plain and st != nil and :bold in st.attrs -> Style.new(attrs: [:bold])
        s.plain -> nil
        true -> st
      end

    label_style = dim(s)
    label_text = "   #{k}: "
    avail_val_w = max(content_w - String.length(label_text), 10)

    case wrap_text(v, avail_val_w) do
      [] ->
        []

      [first | rest] ->
        first_node =
          stack(:horizontal, [text(label_text, label_style), text(first, val_style)])

        rest_nodes =
          Enum.map(rest, fn r ->
            stack(:horizontal, [
              text(String.duplicate(" ", String.length(label_text)), nil),
              text(r, val_style)
            ])
          end)

        [first_node | rest_nodes]
    end
  end

  defp build_task_detail_nodes(t, s, content_w) do
    header_nodes = build_detail_header(t, s, content_w)

    fields =
      base_detail_fields(t, s) ++
        custom_detail_fields(t.tags) ++
        dep_detail_fields(t, s.tasks ++ s.done_tasks)

    field_nodes =
      Enum.flat_map(fields, fn {k, v, st} -> render_field(k, v, st, content_w, s) end)

    header_nodes ++ [text("", nil) | field_nodes]
  end

  defp build_detail_header(t, s, content_w) do
    raw_lines = wrap_text(t.raw, content_w)

    Enum.map(raw_lines, fn line ->
      words = String.split(line, " ", trim: false)
      colored = build_syntax_nodes(words, s, Style.new(attrs: [:bold]))
      stack(:horizontal, [text(" ", nil) | colored])
    end)
  end

  defp base_detail_fields(t, s) do
    recur_val = t.tags["rec"] || t.tags["recur"]

    [
      {"Ligne", "#{t.line}", nil},
      {"Priorité", t.priority && <<t.priority>>, t.priority && pri(s, t.priority)},
      {"Créée", t.creation_date && Date.to_string(t.creation_date), Style.new(fg: :bright_black)},
      {"Faite", t.completion_date && Date.to_string(t.completion_date),
       Style.new(fg: :bright_black)},
      {"Due", t.tags["due"], Style.new(fg: :yellow, attrs: [:bold])},
      {"Seuil t", t.tags["t"], Style.new(fg: :blue, attrs: [:bold])},
      {"Recur", recur_val, Style.new(fg: :yellow)},
      {"Projets", Enum.join(t.projects, " "), Style.new(fg: :cyan, attrs: [:bold])},
      {"Contextes", Enum.join(t.contexts, " "), Style.new(fg: :magenta, attrs: [:bold])}
    ]
  end

  defp custom_detail_fields(tags) do
    known_tags = ["due", "t", "recur", "rec", "pri"]

    tags
    |> Map.drop(known_tags)
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(&format_custom_field/1)
  end

  defp format_custom_field({k, v}) do
    {custom_tag_label(k), custom_tag_value(k, v), custom_tag_style(k)}
  end

  defp custom_tag_label("h"), do: "Masqué h"
  defp custom_tag_label("id"), do: "ID"
  defp custom_tag_label("dep"), do: "Dépendance"
  defp custom_tag_label("p"), do: "Parent"
  defp custom_tag_label("note"), do: "Note"
  defp custom_tag_label("min"), do: "Temps min"
  defp custom_tag_label("count"), do: "Compteur"
  defp custom_tag_label(other), do: String.capitalize(other)

  defp custom_tag_value("min", v), do: "#{v} (#{TimeTracker.format_minutes(v)})"
  defp custom_tag_value(_k, v), do: v

  defp custom_tag_style("h"), do: Style.new(fg: :magenta)
  defp custom_tag_style("id"), do: Style.new(fg: :green, attrs: [:bold])
  defp custom_tag_style("note"), do: Style.new(fg: :cyan)
  defp custom_tag_style("dep"), do: Style.new(fg: :red)
  defp custom_tag_style("p"), do: Style.new(fg: :red)
  defp custom_tag_style("count"), do: Style.new(fg: :yellow)
  defp custom_tag_style("min"), do: Style.new(fg: :blue)
  defp custom_tag_style(_), do: Style.new(fg: :bright_black)

  defp dep_detail_fields(t, all_tasks) do
    case Dependencies.blocking_tasks(t, all_tasks) do
      [] ->
        if Dependencies.parse_deps(t) != [] do
          [{"Statut dep", "Toutes satisfaites", Style.new(fg: :green)}]
        else
          []
        end

      blocking ->
        desc =
          Enum.map_join(blocking, ", ", fn
            %Task{} = b -> "##{b.line}"
            id when is_binary(id) -> "##{id}"
          end)

        [{"Bloqué par", desc, Style.new(fg: :red, attrs: [:bold])}]
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

  defp render_priority_modal(s, modal) do
    modal_w = 26
    inner_w = modal_w - 6
    title = "Priorité"
    border_style = accent(s)

    top_border =
      "╭─ #{title} " <> String.duplicate("─", max(0, modal_w - String.length(title) - 5)) <> "╮"

    bot_border = "╰" <> String.duplicate("─", modal_w - 2) <> "╯"

    widget = modal.widget
    items = Map.get(widget, :filtered_items, Map.get(widget, :original_items, []))
    selected_idx = Map.get(widget, :selected_index, 0)
    scroll_offset = Map.get(widget, :scroll_offset, 0)
    filter_text = Map.get(widget, :filter_text, "")
    visible_count = 9
    visible_items = items |> Enum.drop(scroll_offset) |> Enum.take(visible_count)

    filter_rows = render_priority_filter_rows(filter_text, inner_w, border_style, modal_w)

    item_rows =
      visible_items
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        render_priority_item_row(
          item,
          scroll_offset + idx,
          selected_idx,
          inner_w,
          border_style,
          s
        )
      end)

    pad_rows =
      render_modal_padding_rows(visible_count - length(visible_items), modal_w, border_style)

    status_row = render_priority_status_row(items, selected_idx, inner_w, border_style, s)
    empty_row = modal_empty_row(modal_w, border_style)

    modal_rows =
      [text(top_border, border_style), empty_row] ++
        filter_rows ++
        item_rows ++
        pad_rows ++
        [empty_row, status_row, empty_row, text(bot_border, border_style)]

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

  defp modal_empty_row(modal_w, border_style) do
    stack(:horizontal, [
      text("│", border_style),
      text(String.duplicate(" ", modal_w - 2), nil),
      text("│", border_style)
    ])
  end

  defp render_priority_filter_rows("", _inner_w, _border_style, _modal_w), do: []

  defp render_priority_filter_rows(filter_text, inner_w, border_style, modal_w) do
    filter_str = "Filtre: " <> filter_text
    truncated = String.slice(filter_str, 0, inner_w)
    pad_len = max(0, inner_w - String.length(truncated))

    [
      stack(:horizontal, [
        text("│  ", border_style),
        text(truncated, Style.new(fg: :yellow)),
        text(String.duplicate(" ", pad_len), nil),
        text("  │", border_style)
      ]),
      modal_empty_row(modal_w, border_style)
    ]
  end

  defp render_priority_item_row(item, actual_idx, selected_idx, inner_w, border_style, s) do
    is_selected = actual_idx == selected_idx
    p_byte = if item == "(aucune)", do: nil, else: :binary.first(item)
    base_style = if p_byte, do: pri(s, p_byte), else: dim(s)

    if is_selected do
      padded = String.pad_trailing(item, inner_w)
      sel_style = selected_priority_style(base_style, s)

      stack(:horizontal, [
        text("│  ", border_style),
        text(padded, sel_style),
        text("  │", border_style)
      ])
    else
      pad_len = max(0, inner_w - String.length(item))

      stack(:horizontal, [
        text("│  ", border_style),
        text(item, base_style),
        text(String.duplicate(" ", pad_len), nil),
        text("  │", border_style)
      ])
    end
  end

  defp selected_priority_style(_base_style, %{plain: true}), do: @sel_plain

  defp selected_priority_style(base_style, _s) do
    Style.new(
      fg: base_style.fg || :default,
      bg: :black,
      attrs: MapSet.union(base_style.attrs, MapSet.new([:reverse]))
    )
  end

  defp render_modal_padding_rows(needed_pad, modal_w, border_style) when needed_pad > 0 do
    for _ <- 1..needed_pad, do: modal_empty_row(modal_w, border_style)
  end

  defp render_modal_padding_rows(_needed_pad, _modal_w, _border_style), do: []

  defp render_priority_status_row(items, selected_idx, inner_w, border_style, s) do
    total_items = length(items)
    current_pos = if total_items > 0, do: selected_idx + 1, else: 0
    status_str = "Item #{current_pos} of #{total_items}"
    status_pad_l = max(0, div(inner_w - String.length(status_str), 2))
    status_pad_r = max(0, inner_w - String.length(status_str) - status_pad_l)

    stack(:horizontal, [
      text("│  ", border_style),
      text(String.duplicate(" ", status_pad_l), nil),
      text(status_str, dim(s)),
      text(String.duplicate(" ", status_pad_r), nil),
      text("  │", border_style)
    ])
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

  defp render_tag_modal(s, modal) do
    modal_w = min(max(round(s.width * 0.65), 66), 84)
    inner_w = modal_w - 6
    inner_input_w = inner_w - 2
    title = action_title(:tag, modal) <> " [INS]"
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

    row_helper = fn label_node, label_text ->
      len = String.length(label_text)
      pad = max(0, inner_w - len)

      stack(:horizontal, [
        text("│  ", border_style),
        label_node,
        text(String.duplicate(" ", pad), nil),
        text("  │", border_style)
      ])
    end

    modal_rows = [
      text(top_border, border_style),
      stack(:horizontal, [
        text("│", border_style),
        text(String.duplicate(" ", modal_w - 2), nil),
        text("│", border_style)
      ]),
      row_helper.(
        text("Modifier les métadonnées (clé:valeur ou -clé) :", border_style),
        "Modifier les métadonnées (clé:valeur ou -clé) :"
      ),
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
      row_helper.(text("Exemples :", border_style), "Exemples :"),
      row_helper.(
        text("  • due:YYYY-MM-DD    Échéance (ex: due:today)", Style.new(fg: :red)),
        "  • due:YYYY-MM-DD    Échéance (ex: due:today)"
      ),
      row_helper.(
        text("  • count:N / min:N   Compteur ou durée (minutes)", Style.new(fg: :yellow)),
        "  • count:N / min:N   Compteur ou durée (minutes)"
      ),
      row_helper.(
        text("  • id:ID / dep:ID    Identifiant et dépendances", Style.new(fg: :blue)),
        "  • id:ID / dep:ID    Identifiant et dépendances"
      ),
      row_helper.(
        text("  • -clé              Supprime le tag (ex: -due, -dep)", dim(s)),
        "  • -clé              Supprime le tag (ex: -due, -dep)"
      ),
      stack(:horizontal, [
        text("│", border_style),
        text(String.duplicate(" ", modal_w - 2), nil),
        text("│", border_style)
      ]),
      row_helper.(
        text("[Ctrl+U] Vider   [Entrée] Appliquer   [Échap] Annuler", dim(s)),
        "[Ctrl+U] Vider   [Entrée] Appliquer   [Échap] Annuler"
      ),
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

  defp render_help_modal(s, _modal) do
    modal_w = min(max(round(s.width * 0.80), 70), 92)
    inner_w = modal_w - 6
    border_style = accent(s)
    title = "AIDE & RACCOURCIS [?]"

    top_border =
      "╭─ #{title} " <> String.duplicate("─", max(0, modal_w - String.length(title) - 5)) <> "╮"

    bot_border = "╰" <> String.duplicate("─", modal_w - 2) <> "╯"

    line_helper = fn node, raw_len ->
      pad = max(0, inner_w - raw_len)

      stack(:horizontal, [
        text("│  ", border_style),
        node,
        text(String.duplicate(" ", pad), nil),
        text("  │", border_style)
      ])
    end

    sec_title = fn title_text, color ->
      node = text("▸ " <> title_text, Style.new(fg: color, attrs: [:bold]))
      line_helper.(node, String.length("▸ " <> title_text))
    end

    shortcut_line = fn key, desc ->
      key_node = text("  " <> String.pad_trailing(key, 12), token_key_style(s))
      desc_node = text(desc, token_desc_style(s))
      node = stack(:horizontal, [key_node, desc_node])
      line_helper.(node, 2 + max(String.length(key), 12) + String.length(desc))
    end

    empty_line =
      stack(:horizontal, [
        text("│", border_style),
        text(String.duplicate(" ", modal_w - 2), nil),
        text("│", border_style)
      ])

    modal_rows = [
      text(top_border, border_style),
      empty_line,
      sec_title.("Navigation & Sélection", :green),
      shortcut_line.("j / k", "Déplacer la sélection bas / haut (ou flèches ↑/↓)"),
      shortcut_line.("Tab / l", "Aller à la liste des tâches (ou h pour le menu latéral)"),
      empty_line,
      sec_title.("Actions sur les tâches", :cyan),
      shortcut_line.("x / Espace", "Terminer une tâche (gère count:N et récurrence recur:)"),
      shortcut_line.("a / e", "Ajouter une nouvelle tâche / Modifier la tâche courante"),
      shortcut_line.("A / P", "Ajouter du texte à la fin / au début de la tâche"),
      shortcut_line.("p", "Changer la priorité (A-Z ou aucune)"),
      shortcut_line.("t", "Éditer les tags et champs spéciaux (ex: due:2026-10-15 ou -due)"),
      shortcut_line.("d / m", "Supprimer la tâche / Déplacer entre todo.txt et done.txt"),
      empty_line,
      sec_title.("Vues, Filtres & Recherche", :yellow),
      shortcut_line.(
        "/",
        "Recherche / filtrage par texte, +projet ou @contexte (Esc pour effacer)"
      ),
      shortcut_line.(
        "L / H",
        "Basculer la portée (Local ↔ Global) / Afficher les masquées (h:1)"
      ),
      empty_line,
      sec_title.("Notes, Outils & Système", :magenta),
      shortcut_line.("N", "Éditer la note Markdown associée ($EDITOR)"),
      shortcut_line.("E / R", "Ouvrir tout todo.txt ($EDITOR) / Archiver les tâches terminées"),
      shortcut_line.("r / ^L / q", "Recharger fichiers / Redessiner écran / Quitter"),
      empty_line,
      line_helper.(text("[ Échap / Entrée / ? / q ]  Fermer l'aide", dim(s)), 40),
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

  defp render_confirm_modal(s, modal) do
    modal_w = min(max(round(s.width * 0.52), 48), 64)
    inner_w = modal_w - 6
    border_style = accent(s)
    title = if modal.action == :del, do: "SUPPRIMER", else: "ARCHIVER"

    question =
      case modal.action do
        :del -> "Supprimer la tâche ##{modal[:line]} ?"
        :archive -> "Archiver les tâches terminées dans done.txt ?"
        _ -> "Confirmer cette action ?"
      end

    top_border =
      "╭─ #{title} " <> String.duplicate("─", max(0, modal_w - String.length(title) - 5)) <> "╮"

    bot_border = "╰" <> String.duplicate("─", modal_w - 2) <> "╯"

    empty_line =
      stack(:horizontal, [
        text("│", border_style),
        text(String.duplicate(" ", modal_w - 2), nil),
        text("│", border_style)
      ])

    pad_q = max(0, inner_w - String.length(question))
    left_q = div(pad_q, 2)
    right_q = pad_q - left_q

    question_row =
      stack(:horizontal, [
        text("│  ", border_style),
        text(String.duplicate(" ", left_q), nil),
        text(question, Style.new(fg: :yellow, attrs: [:bold])),
        text(String.duplicate(" ", right_q), nil),
        text("  │", border_style)
      ])

    hint = "[ Entrée / O ] Confirmer    [ Échap / N ] Annuler"
    pad_h = max(0, inner_w - String.length(hint))
    left_h = div(pad_h, 2)
    right_h = pad_h - left_h

    hint_row =
      stack(:horizontal, [
        text("│  ", border_style),
        text(String.duplicate(" ", left_h), nil),
        text(hint, dim(s)),
        text(String.duplicate(" ", right_h), nil),
        text("  │", border_style)
      ])

    modal_rows = [
      text(top_border, border_style),
      empty_line,
      question_row,
      empty_line,
      hint_row,
      empty_line,
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

    input_row_nodes = build_input_rows(val, modal.widget, inner_input_w, border_style)
    preview_row_nodes = build_preview_rows(val, s, inner_w, border_style)
    legend_row_nodes = build_legend_rows(s, inner_w, border_style)
    tags_badge_nodes = build_tags_badge_rows(task, inner_w, modal_w, border_style)

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
        ])
      ] ++
        input_row_nodes ++
        legend_row_nodes ++
        [
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
        tags_badge_nodes ++
        [
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
    top_pad = max(div(body_height(s) - box_h, 2), 0)
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

  defp build_input_rows(val, widget, inner_input_w, border_style) do
    cursor_pos = Map.get(widget, :cursor_col, String.length(val))
    {lines, cur_line, cur_col} = wrap_input_with_cursor(val, cursor_pos, inner_input_w)

    Enum.with_index(lines, fn line, idx ->
      line_node = render_input_line(line, idx == cur_line, cur_col, inner_input_w)
      prefix = if idx == 0, do: "│  > ", else: "│    "

      stack(:horizontal, [
        text(prefix, border_style),
        line_node,
        text("  │", border_style)
      ])
    end)
  end

  defp build_preview_rows(val, s, inner_w, border_style) do
    preview_lines = wrap_text(val, inner_w)
    preview_lines = if preview_lines == [], do: [""], else: preview_lines

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
  end

  defp build_legend_rows(s, inner_w, border_style) do
    tokens = [
      {"Syntaxe :", dim(s)},
      {"+projet", Style.new(fg: :cyan, attrs: [:bold])},
      {"@contexte", Style.new(fg: :magenta, attrs: [:bold])},
      {"(A)", pri(s, ?A)},
      {"due:AAAA-MM-JJ", Style.new(fg: :yellow, attrs: [:bold])},
      {"t:AAAA-MM-JJ", Style.new(fg: :blue, attrs: [:bold])},
      {"rec:1w", Style.new(fg: :yellow)},
      {"count:N", Style.new(fg: :yellow)},
      {"min:MIN", Style.new(fg: :blue)},
      {"id:ID", Style.new(fg: :green, attrs: [:bold])},
      {"dep:ID", Style.new(fg: :red)},
      {"note:NOTE", Style.new(fg: :cyan)},
      {"h:1", Style.new(fg: :magenta)}
    ]

    wrapped_lines = wrap_legend_tokens(tokens, inner_w)
    Enum.map(wrapped_lines, &build_single_legend_row(&1, inner_w, border_style))
  end

  defp build_single_legend_row(line_tokens, inner_w, border_style) do
    row_nodes = format_legend_token_nodes(line_tokens)
    total_len = legend_line_length(line_tokens)
    pad = max(0, inner_w - total_len)

    stack(:horizontal, [
      text("│  ", border_style),
      stack(:horizontal, row_nodes),
      text(String.duplicate(" ", pad), nil),
      text("  │", border_style)
    ])
  end

  defp format_legend_token_nodes(line_tokens) do
    Enum.flat_map(Enum.with_index(line_tokens), fn {{text_str, style}, idx} ->
      sep = if idx > 0, do: [text(" ", nil)], else: []
      sep ++ [text(text_str, style)]
    end)
  end

  defp legend_line_length(line_tokens) do
    text_lens = Enum.map(line_tokens, fn {text_str, _} -> String.length(text_str) end)
    Enum.sum(text_lens) + max(0, length(line_tokens) - 1)
  end

  defp wrap_legend_tokens(tokens, max_w) do
    do_wrap_legend_tokens(tokens, max_w, 0, [], [])
  end

  defp do_wrap_legend_tokens([], _max_w, _curr_len, current_line, acc) do
    Enum.reverse([Enum.reverse(current_line) | acc])
  end

  defp do_wrap_legend_tokens([{str, _} = token | rest], max_w, curr_len, current_line, acc) do
    token_len = String.length(str)
    added_len = if current_line == [], do: token_len, else: token_len + 1

    if curr_len + added_len <= max_w or current_line == [] do
      do_wrap_legend_tokens(rest, max_w, curr_len + added_len, [token | current_line], acc)
    else
      do_wrap_legend_tokens(
        [token | rest],
        max_w,
        0,
        [],
        [Enum.reverse(current_line) | acc]
      )
    end
  end

  defp build_tags_badge_rows(task, inner_w, modal_w, border_style) do
    badges = collect_task_badges(task)

    if badges == [] do
      [
        stack(:horizontal, [
          text("│", border_style),
          text(String.duplicate(" ", modal_w - 2), nil),
          text("│", border_style)
        ])
      ]
    else
      full_text = Enum.join(badges, "  ·  ")
      wrapped_lines = wrap_text(full_text, inner_w)

      Enum.map(wrapped_lines, fn line ->
        pad = max(0, inner_w - String.length(line))

        stack(:horizontal, [
          text("│  ", border_style),
          text(line, Style.new(fg: :green)),
          text(String.duplicate(" ", pad), nil),
          text("  │", border_style)
        ])
      end)
    end
  end

  defp collect_task_badges(task) do
    header_badges(task) ++ special_tag_badges(task.tags) ++ other_tag_badges(task.tags)
  end

  defp header_badges(task) do
    prio_str = if task.priority, do: "Prio [#{<<task.priority>>}]"
    proj_str = if task.projects != [], do: Enum.join(task.projects, " ")
    ctx_str = if task.contexts != [], do: Enum.join(task.contexts, " ")

    []
    |> maybe_append(prio_str, prio_str)
    |> maybe_append(proj_str, proj_str)
    |> maybe_append(ctx_str, ctx_str)
  end

  defp special_tag_badges(tags) do
    recur = tags["rec"] || tags["recur"]

    min_desc =
      if Map.has_key?(tags, "min"),
        do: "#{tags["min"]} (#{TimeTracker.format_minutes(tags["min"])})"

    []
    |> maybe_append(tags["due"], "due:#{tags["due"]}")
    |> maybe_append(tags["t"], "t:#{tags["t"]}")
    |> maybe_append(recur, "rec:#{recur}")
    |> maybe_append(tags["count"], "count:#{tags["count"]}")
    |> maybe_append(min_desc, "min:#{min_desc}")
    |> maybe_append(tags["id"], "id:#{tags["id"]}")
    |> maybe_append(tags["dep"], "dep:#{tags["dep"]}")
    |> maybe_append(tags["note"], "note:#{tags["note"]}")
    |> maybe_append(tags["h"], "h:1")
  end

  defp other_tag_badges(tags) do
    handled = ["due", "t", "rec", "recur", "count", "min", "id", "dep", "note", "h", "pri"]

    tags
    |> Map.drop(handled)
    |> Enum.map(fn {k, v} -> "#{k}:#{v}" end)
  end

  defp maybe_append(list, cond_val, _val) when cond_val in [nil, false], do: list
  defp maybe_append(list, _cond_val, val), do: list ++ [val]

  defp wrap_input_with_cursor("", _cursor_pos, _max_w) do
    {[""], 0, 0}
  end

  defp wrap_input_with_cursor(text, cursor_pos, max_w) do
    tokens = Regex.scan(~r/\S+\s*|\s+/, text) |> List.flatten()
    lines = do_input_wrap(tokens, max_w, "", [])
    {cursor_line, cursor_col} = find_cursor_pos(lines, cursor_pos, 0, 0)
    {lines, cursor_line, cursor_col}
  end

  defp do_input_wrap([], _max_w, current, acc) do
    if current == "", do: Enum.reverse(acc), else: Enum.reverse([current | acc])
  end

  defp do_input_wrap([tok | rest], max_w, "", acc) do
    if String.length(tok) > max_w do
      {head, tail} = String.split_at(tok, max_w)
      do_input_wrap([tail | rest], max_w, "", [head | acc])
    else
      do_input_wrap(rest, max_w, tok, acc)
    end
  end

  defp do_input_wrap([tok | rest], max_w, current, acc) do
    if String.length(current <> tok) <= max_w do
      do_input_wrap(rest, max_w, current <> tok, acc)
    else
      do_input_wrap([tok | rest], max_w, "", [current | acc])
    end
  end

  defp find_cursor_pos([_last_line], cursor_pos, cur_idx, line_start) do
    {cur_idx, max(0, cursor_pos - line_start)}
  end

  defp find_cursor_pos([line | rest], cursor_pos, cur_idx, line_start) do
    line_end = line_start + String.length(line)

    if cursor_pos < line_end do
      {cur_idx, cursor_pos - line_start}
    else
      find_cursor_pos(rest, cursor_pos, cur_idx + 1, line_end)
    end
  end

  defp render_input_line(line, true, col, max_w) do
    line_len = String.length(line)

    if col < line_len do
      before_txt = String.slice(line, 0, col)
      cur_char = String.slice(line, col, 1)
      after_txt = String.slice(line, (col + 1)..-1//1)
      disp_char = if cur_char in [" ", ""], do: "█", else: cur_char
      cursor_st = Style.new(fg: :cyan, bg: :black, attrs: [:reverse, :bold])
      pad = max(0, max_w - line_len)

      stack(:horizontal, [
        text(before_txt, nil),
        text(disp_char, cursor_st),
        text(after_txt, nil),
        text(String.duplicate(" ", pad), nil)
      ])
    else
      cursor_st = Style.new(fg: :cyan, bg: :black, attrs: [:reverse, :bold])
      pad = max(0, max_w - (line_len + 1))

      stack(:horizontal, [
        text(line, nil),
        text("█", cursor_st),
        text(String.duplicate(" ", pad), nil)
      ])
    end
  end

  defp render_input_line(line, false, _col, max_w) do
    pad = max(0, max_w - String.length(line))
    stack(:horizontal, [text(line, nil), text(String.duplicate(" ", pad), nil)])
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

  defp action_title(:help, _m), do: "AIDE & RACCOURCIS"
  defp action_title(:del, m), do: "SUPPRIMER LA TÂCHE ##{m[:line]}"
  defp action_title(:archive, _m), do: "ARCHIVER LES TÂCHES"
  defp action_title(:add, _m), do: "NOUVELLE TÂCHE"
  defp action_title(:tag, m), do: "ÉDITER LES TAGS ##{m[:line]}"
  defp action_title(:edit, m), do: "MODIFIER LA TÂCHE ##{m[:line]}"
  defp action_title(:append, m), do: "AJOUTER À LA FIN ##{m[:line]}"
  defp action_title(:prepend, m), do: "AJOUTER AU DÉBUT ##{m[:line]}"
  defp action_title(a, _m), do: a |> Atom.to_string() |> String.upcase()

  defp build_syntax_nodes(words, s, default_style \\ nil) do
    Enum.flat_map(Enum.with_index(words), fn {w, i} ->
      prefix = if i > 0, do: [text(" ", nil)], else: []
      style = word_style(w, s) || default_style
      prefix ++ [text(w, style)]
    end)
  end

  defp word_style(w, %{plain: true} = s) do
    cond do
      String.starts_with?(w, "due:") ->
        due_style(w, s)

      String.match?(w, ~r/^\([A-Z]\)$/) or String.starts_with?(w, "+") or
          String.starts_with?(w, "@") ->
        Style.new(attrs: [:bold])

      true ->
        nil
    end
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
        due_style(w, s)

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

  defp due_style(w, %{plain: true}) do
    val = String.replace_prefix(w, "due:", "")

    if valid_due_val?(val),
      do: Style.new(attrs: [:bold]),
      else: Style.new(attrs: [:bold, :underline])
  end

  defp due_style(w, _s) do
    val = String.replace_prefix(w, "due:", "")

    if valid_due_val?(val),
      do: Style.new(fg: :yellow, attrs: [:bold]),
      else: Style.new(fg: :red, attrs: [:bold, :underline])
  end

  defp valid_due_val?(val) do
    case Date.from_iso8601(val) do
      {:ok, _} -> true
      _ -> val != "" and Regex.match?(~r/^[a-zA-Z]+$/, val)
    end
  end

  def statusline_height(%{mode: :input}), do: 3

  def statusline_height(s) do
    2 + length(shortcuts_lines(s))
  end

  defp statusline(%{mode: :input, modal: %{action: a}} = s)
       when a in [:add, :edit, :append, :prepend, :tag, :help, :del, :archive] do
    sep = text(build_separator(s), dim(s))
    action_label = action_title(a, s.modal)
    scope = if s.local, do: "[LOCAL]", else: "[GLOBAL]"
    line1 = text(" #{action_label} #{scope}", accent(s))

    line2 =
      cond do
        a == :help ->
          text(" [Échap / Entrée / ? / q] Fermer l'aide", dim(s))

        a in [:del, :archive] ->
          text(" [Entrée / O] Confirmer    [Échap / N] Annuler", dim(s))

        true ->
          text(" [Entrée] Valider    [Échap] Annuler", dim(s))
      end

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
    shortcut_nodes = shortcuts_lines(s)

    stack(:vertical, [sep, line1 | shortcut_nodes])
  end

  defp build_separator(s) do
    width = max(s.width, 1)
    detail_w = max(round(width * 0.30), 24)
    sb_col = 20
    detail_col = max(width - detail_w, sb_col + 1)

    chars =
      for col <- 0..(width - 1) do
        cond do
          col == sb_col and col < width - 1 -> "┴"
          col == detail_col and col < width - 1 -> "┴"
          true -> "─"
        end
      end

    Enum.join(chars)
  end

  # --- Design Tokens: Statusline Shortcuts ---
  defp token_bracket_style(%{plain: true}), do: @dim_plain
  defp token_bracket_style(_), do: Style.new(fg: :bright_black)

  defp token_group_style(%{plain: true}, _group), do: @dim_plain
  defp token_group_style(_, :task), do: Style.new(fg: :bright_cyan, attrs: [:bold])
  defp token_group_style(_, :nav), do: Style.new(fg: :bright_green, attrs: [:bold])
  defp token_group_style(_, :sys), do: Style.new(fg: :bright_magenta, attrs: [:bold])

  defp token_key_style(%{plain: true}), do: @dim_plain
  defp token_key_style(_), do: Style.new(fg: :bright_yellow, attrs: [:bold])

  defp token_desc_style(%{plain: true}), do: @dim_plain
  defp token_desc_style(_), do: Style.new(fg: :white)

  defp token_sep_style(%{plain: true}), do: @dim_plain
  defp token_sep_style(_), do: Style.new(fg: :bright_black)

  defp shortcuts_lines(s) do
    groups = shortcut_groups(s)
    max_w = max((s.width || 80) - 2, 20)
    wrap_shortcut_groups(groups, max_w, s)
  end

  defp shortcut_groups(%{focus: :sidebar}) do
    [
      {:nav, "Navigation",
       [
         {"Tab/l", "Liste"},
         {"j/k", "Naviguer"},
         {"Entrée", "Filtrer"},
         {"/", "Filtrer"}
       ]},
      {:sys, "Système",
       [
         {"^L", "Nettoyer"},
         {"?", "Aide"},
         {"q", "Quitter"}
       ]}
    ]
  end

  defp shortcut_groups(s) do
    selected = State.selected_task(s)
    is_done = s.view == :done or (selected != nil and selected.done)
    x_label = if is_done, do: "Reprendre", else: "Terminer"

    note_item = if is_integer(s.width) and s.width >= 180, do: [{"N", "Note"}], else: []

    [
      {:task, "Tâche",
       [
         {"a", "Ajouter"},
         {"e", "Modifier"},
         {"x", x_label},
         {"d", "Supprimer"},
         {"p", "Priorité"}
       ]},
      {:nav, "Vue",
       [
         {"Tab/h", "Menu"},
         {"m", "Déplacer"},
         {"L", "Scope"},
         {"H", "h:1"},
         {"/", "Filtrer"}
       ]},
      {:sys, "Système",
       note_item ++
         [
           {"E", "Éditeur"},
           {"^L", "Nettoyer"},
           {"?", "Aide"},
           {"q", "Quitter"}
         ]}
    ]
  end

  defp wrap_shortcut_groups(groups, max_w, s) do
    rendered_groups = Enum.map(groups, &render_group_info(&1, s))
    pack_groups_into_lines(rendered_groups, max_w, s)
  end

  defp render_group_info({group_id, title, items}, s) do
    header_len = String.length(title) + 3

    header_nodes = [
      text("[", token_bracket_style(s)),
      text(title, token_group_style(s, group_id)),
      text("] ", token_bracket_style(s))
    ]

    item_entries =
      Enum.map(items, fn {k, desc} ->
        nodes = [
          text(k, token_key_style(s)),
          text(":", token_sep_style(s)),
          text(desc, token_desc_style(s))
        ]

        len = String.length(k) + 1 + String.length(desc)
        {nodes, len}
      end)

    items_len =
      item_entries
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()
      |> Kernel.+(max(0, length(item_entries) - 1))

    total_len = header_len + items_len

    all_nodes =
      header_nodes ++
        Enum.flat_map(Enum.with_index(item_entries), fn {{nodes, _len}, idx} ->
          sep = if idx > 0, do: [text(" ", nil)], else: []
          sep ++ nodes
        end)

    %{len: total_len, nodes: all_nodes}
  end

  defp pack_groups_into_lines([], _max_w, _s), do: []

  defp pack_groups_into_lines(groups, max_w, s) do
    do_pack_groups(groups, max_w, s, 0, [], [])
  end

  defp do_pack_groups([], _max_w, _s, _curr_len, current_line, acc) do
    Enum.reverse([finish_line(current_line) | acc])
  end

  defp do_pack_groups([group | rest], max_w, s, curr_len, current_line, acc) do
    sep_len = if current_line == [], do: 1, else: 3
    added_len = sep_len + group.len

    if curr_len + added_len <= max_w or current_line == [] do
      new_nodes =
        if current_line == [] do
          group.nodes
        else
          current_line ++ [text(" │ ", token_sep_style(s)) | group.nodes]
        end

      do_pack_groups(rest, max_w, s, curr_len + added_len, new_nodes, acc)
    else
      do_pack_groups(rest, max_w, s, 1 + group.len, group.nodes, [finish_line(current_line) | acc])
    end
  end

  defp finish_line(nodes), do: stack(:horizontal, [text(" ", nil) | nodes])
end
