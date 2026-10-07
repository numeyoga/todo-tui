defmodule TodoTxt.Tui.RatatuiRenderer do
  @moduledoc """
  Translates the pure `TodoTxt.Tui.View` RenderNode tree into `ExRatatui` widgets and rects.
  """

  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Text.Line
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.{Clear, Paragraph}
  alias TermUI.Component.RenderNode
  alias TermUI.Renderer.Style, as: TermStyle
  alias TodoTxt.Tui.View

  @doc "Renders state and frame into a list of `{widget, rect}` tuples for ExRatatui."
  def render(state, frame) do
    w = max(frame.width, 1)
    h = max(frame.height, 1)
    state = Map.merge(state, %{width: w, height: h})

    if Map.get(state, :redraw_clearing, false) do
      root_rect = %Rect{x: 0, y: 0, width: w, height: h}
      [{%Clear{}, root_rect}]
    else
      tree = View.render(state)

      root_rect = %Rect{x: 0, y: 0, width: w, height: h}
      status_h = View.statusline_height(state)

      [header_rect, body_rect, status_rect] =
        Layout.split(root_rect, :vertical, [
          {:length, 2},
          {:fill, 1},
          {:length, status_h}
        ])

      {header_node, body_node, status_node} = unpack_root(tree)

      header_w = %Paragraph{text: to_ratatui_lines(header_node)}
      status_w = %Paragraph{text: to_ratatui_lines(status_node)}

      base_widgets = [
        {header_w, header_rect},
        {status_w, status_rect}
      ]

      body_widgets =
        if state.mode == :input and not is_nil(state.modal) do
          # Modal is open: render modal overlay over body
          modal_w = %Paragraph{text: to_ratatui_lines(body_node)}
          [{%Clear{}, body_rect}, {modal_w, body_rect}]
        else
          # 3-pane body
          render_3pane(body_node, body_rect, w)
        end

      base_widgets ++ body_widgets
    end
  end

  defp unpack_root(%RenderNode{children: [{h, _}, {b, _}, {s, _}]}), do: {h, b, s}
  defp unpack_root(%RenderNode{children: [h, b, s]}), do: {h, b, s}
  defp unpack_root(_), do: {%RenderNode{}, %RenderNode{}, %RenderNode{}}

  defp render_3pane(%RenderNode{children: children}, body_rect, width) do
    {sb_node, list_node, detail_node} = unpack_body(children)

    detail_w = max(round(width * 0.30), 24)

    [sb_rect, list_rect, detail_rect] =
      Layout.split(body_rect, :horizontal, [
        {:length, 21},
        {:fill, 1},
        {:length, detail_w}
      ])

    [
      {%Paragraph{text: to_ratatui_lines(sb_node)}, sb_rect},
      {%Paragraph{text: to_ratatui_lines(list_node)}, list_rect},
      {%Paragraph{text: to_ratatui_lines(detail_node)}, detail_rect}
    ]
  end

  defp unpack_body([{sb, _}, {l, _}, {d, _}]), do: {sb, l, d}
  defp unpack_body([sb, l, d]), do: {sb, l, d}
  defp unpack_body(_), do: {%RenderNode{}, %RenderNode{}, %RenderNode{}}

  @doc "Converts a RenderNode into a list of ExRatatui.Text.Line structs."
  def to_ratatui_lines(%{type: :overlay, content: content}), do: to_ratatui_lines(content)
  def to_ratatui_lines({node, _constraint}), do: to_ratatui_lines(node)

  def to_ratatui_lines(%RenderNode{type: :stack, direction: :vertical, children: children}) do
    Enum.map(children, &to_ratatui_line/1)
  end

  def to_ratatui_lines(
        %RenderNode{type: :stack, direction: :horizontal, children: children} = node
      ) do
    if Enum.any?(children, &column?/1) do
      merge_columns(children)
    else
      [to_ratatui_line(node)]
    end
  end

  def to_ratatui_lines(%RenderNode{type: :box, children: children}) do
    Enum.map(children, &to_ratatui_line/1)
  end

  def to_ratatui_lines(node) do
    [to_ratatui_line(node)]
  end

  defp column?({child, _constraint}), do: column?(child)
  defp column?(%RenderNode{type: :stack, direction: :vertical}), do: true
  defp column?(%RenderNode{type: :box}), do: true
  defp column?(_), do: false

  defp unwrap_child({node, _constraint}), do: node
  defp unwrap_child(node), do: node

  defp merge_columns(children) do
    columns_lines = Enum.map(children, fn child -> to_ratatui_lines(unwrap_child(child)) end)

    max_lines =
      columns_lines
      |> Enum.map(&length/1)
      |> Enum.max(fn -> 0 end)

    for idx <- 0..(max_lines - 1)//1, max_lines > 0 do
      Line.new(row_spans(columns_lines, idx))
    end
  end

  defp row_spans(columns_lines, idx) do
    Enum.flat_map(columns_lines, &column_spans_at(&1, idx))
  end

  defp column_spans_at(col_lines, idx) do
    case Enum.at(col_lines, idx) do
      %Line{spans: col_spans} -> col_spans
      _ -> []
    end
  end

  defp to_ratatui_line({node, _constraint}), do: to_ratatui_line(node)

  defp to_ratatui_line(%RenderNode{type: :stack, direction: :horizontal, children: children}) do
    spans = Enum.flat_map(children, &extract_spans/1)
    Line.new(spans)
  end

  defp to_ratatui_line(%RenderNode{type: :box, style: box_style, children: children}) do
    spans = Enum.flat_map(children, &extract_spans(&1, box_style))
    Line.new(spans)
  end

  defp to_ratatui_line(%RenderNode{type: :text, content: content, style: style}) do
    Line.new([Span.new(content || "", style: to_ratatui_style(style))])
  end

  defp to_ratatui_line(_), do: Line.new([])

  defp extract_spans({node, _constraint}), do: extract_spans(node)

  defp extract_spans(%RenderNode{type: :text, content: content, style: style}) do
    [Span.new(content || "", style: to_ratatui_style(style))]
  end

  defp extract_spans(%RenderNode{type: :box, style: box_style, children: children}) do
    Enum.flat_map(children, &extract_spans(&1, box_style))
  end

  defp extract_spans(%RenderNode{type: :stack, direction: :horizontal, children: children}) do
    Enum.flat_map(children, &extract_spans/1)
  end

  defp extract_spans(_), do: []

  defp extract_spans({node, _constraint}, parent_style), do: extract_spans(node, parent_style)

  defp extract_spans(%RenderNode{type: :text, content: content, style: style}, parent_style) do
    effective_style = style || parent_style
    [Span.new(content || "", style: to_ratatui_style(effective_style))]
  end

  defp extract_spans(%RenderNode{type: :box, style: box_style, children: children}, parent_style) do
    effective_style = box_style || parent_style
    Enum.flat_map(children, &extract_spans(&1, effective_style))
  end

  defp extract_spans(
         %RenderNode{type: :stack, direction: :horizontal, children: children},
         parent_style
       ) do
    Enum.flat_map(children, &extract_spans(&1, parent_style))
  end

  defp extract_spans(_, _), do: []

  @color_map %{
    bright_black: :dark_gray,
    bright_red: :light_red,
    bright_green: :light_green,
    bright_yellow: :light_yellow,
    bright_blue: :light_blue,
    bright_magenta: :light_magenta,
    bright_cyan: :light_cyan,
    bright_white: :white
  }

  @attr_map %{
    bold: :bold,
    dim: :dim,
    reverse: :reversed,
    italic: :italic,
    underline: :underlined
  }

  @doc "Converts TermUI Style to ExRatatui Style."
  def to_ratatui_style(nil), do: %ExRatatui.Style{}

  def to_ratatui_style(%TermStyle{fg: fg, bg: bg, attrs: attrs}) do
    %ExRatatui.Style{
      fg: convert_color(fg),
      bg: convert_color(bg),
      modifiers: convert_attrs(attrs)
    }
  end

  def to_ratatui_style(%ExRatatui.Style{} = s), do: s

  defp convert_color(c) when is_atom(c) and c != :default do
    Map.get(@color_map, c, c)
  end

  defp convert_color(_), do: nil

  defp convert_attrs(attrs) do
    attrs
    |> Enum.map(&Map.get(@attr_map, &1))
    |> Enum.reject(&is_nil/1)
  end
end
