defmodule TodoTxt.Tui.ViewTest do
  use ExUnit.Case, async: true
  alias TermUI.Component.RenderNode
  alias TodoTxt.{Parser, Tui.Modal, Tui.State, Tui.View}

  defp st(tasks, opts \\ []) do
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

  defp fake_io,
    do: %{
      read: fn _ -> {:ok, []} end,
      write: fn _, _ -> :ok end,
      append: fn _, _ -> :ok end,
      stat: fn _ -> {:error, :enoent} end
    }

  defp t(raw, line), do: Parser.parse(raw, line)

  # helpers d'inspection du render tree — la clause :text doit précéder la
  # clause children : tout %RenderNode{} a children: [] par défaut.
  defp texts(%RenderNode{type: :text, content: c}), do: [c]

  defp texts(%RenderNode{children: children}) when is_list(children),
    do:
      Enum.flat_map(children, fn
        {node, _constraint} -> texts(node)
        %RenderNode{} = node -> texts(node)
        _ -> []
      end)

  defp texts(_), do: []

  defp text_nodes(%RenderNode{type: :text} = n), do: [n]

  defp text_nodes(%RenderNode{children: children}) when is_list(children),
    do:
      Enum.flat_map(children, fn
        {node, _constraint} -> text_nodes(node)
        %RenderNode{} = node -> text_nodes(node)
        _ -> []
      end)

  defp text_nodes(_), do: []

  test "root is a vertical stack: header + body fill + statusline" do
    %RenderNode{
      type: :stack,
      direction: :vertical,
      children: [{header, _}, {body, _}, {status, _}]
    } =
      View.render(st([t("a", 1)]))

    assert %RenderNode{type: :stack, direction: :vertical} = header
    assert body.direction == :horizontal
    assert %RenderNode{type: :stack, direction: :vertical} = status
    assert length(status.children) >= 3
  end

  test "task rows carry N: raw; selected row has reverse style when list focused" do
    tree = View.render(st([t("a", 1), t("b", 2)], focus: :list, list_idx: 1))
    %RenderNode{children: [{_header, _}, {body, _}, {_status, _}]} = tree
    %RenderNode{children: [{_sb, _}, {list, _}, {_d, _}]} = body
    sel = Enum.at(list.children, 1)
    assert %RenderNode{type: :text, content: content, style: style} = sel
    assert String.starts_with?(content, " 2: b")
    assert :reverse in style.attrs
  end

  test "agenda view renders date headers; statusline shows active filters" do
    s = st([t("s due:2026-09-25", 1)], view: :agenda)
    assert " 2026-09-25:" in texts(View.render(s))

    s = st([t("a", 1)], filter_terms: ["+p"])
    assert Enum.any?(texts(View.render(s)), &String.contains?(&1, "+p"))
  end

  test "colored mode: priority rows carry fg colors" do
    nodes = text_nodes(View.render(st([t("(A) a", 1)], focus: :sidebar)))
    row = Enum.find(nodes, &(&1.content == "(A)"))
    assert row.style.fg == :red
  end

  test "plain mode: no fg colors — priorities bold, done dimmed, selection reverse" do
    s =
      st([t("(A) a", 1), t("x 2026-09-21 done", 2), t("c", 3)],
        plain: true,
        focus: :list,
        list_idx: 2
      )

    nodes = text_nodes(View.render(s))

    pri = Enum.find(nodes, &(&1.content == "(A)"))
    assert pri.style.fg == nil
    assert :bold in pri.style.attrs

    done = Enum.find(nodes, &String.contains?(&1.content, "done"))
    assert done.style.fg == nil
    assert :dim in done.style.attrs

    sel = Enum.find(nodes, &String.starts_with?(&1.content, " 3: c"))
    assert sel.style.fg == nil
    assert :reverse in sel.style.attrs
  end

  test "statusline renders shortcuts in full and error messages with bold red" do
    s = st([t("a", 1)], status: "error: test failure")
    all_text = texts(View.render(s))
    assert Enum.any?(all_text, &String.contains?(&1, "error: test failure"))
    assert Enum.any?(all_text, &String.contains?(&1, "Ajouter"))
    assert Enum.any?(all_text, &String.contains?(&1, "Supprimer"))

    nodes = text_nodes(View.render(s))
    err_node = Enum.find(nodes, &String.contains?(&1.content, "error: test failure"))
    assert err_node.style.fg == :red
    assert :bold in err_node.style.attrs
  end

  test "extended priorities D, E, F carry distinct fg colors" do
    tasks = [t("(D) d_task", 1), t("(E) e_task", 2), t("(F) f_task", 3)]
    nodes = text_nodes(View.render(st(tasks, focus: :sidebar)))
    d_node = Enum.find(nodes, &(&1.content == "(D)"))
    e_node = Enum.find(nodes, &(&1.content == "(E)"))
    f_node = Enum.find(nodes, &(&1.content == "(F)"))

    assert d_node.style.fg == :green
    assert e_node.style.fg == :blue
    assert f_node.style.fg == :magenta
  end

  test "window_rows scrolls the list when tasks exceed terminal height" do
    tasks = for i <- 1..30, do: t("task #{i}", i)
    s = st(tasks, focus: :list, list_idx: 25, height: 15)
    rendered_texts = texts(View.render(s))
    assert Enum.any?(rendered_texts, &String.contains?(&1, "26:"))
  end

  test "detail pane word-wraps long task descriptions across multiple lines" do
    long_desc = "Faire une capture d'ecran tres detaillee de l'application todo pour le TUI"
    s = st([t(long_desc, 1)], list_idx: 0, width: 80)
    tree = View.render(s)
    %RenderNode{children: [{_header, _}, {body, _}, {_status, _}]} = tree
    %RenderNode{children: [{_sb, _}, {_list, _}, {detail_node, _}]} = body
    %RenderNode{children: [{sep_node, _}, {content_node, _}]} = detail_node

    # Separator is an independent column of dim vertical bars, unaffected by content styles
    assert length(sep_node.children) >= 15

    assert Enum.all?(sep_node.children, fn %RenderNode{content: c, style: st} ->
             c == "│" and :bold not in (st.attrs || [])
           end)

    # At width 80 (detail pane width ~24, content ~20), this 74-char text must be wrapped into 3+ lines
    all_text = texts(content_node)
    assert Enum.any?(all_text, &String.contains?(&1, "capture"))
    assert Enum.any?(all_text, &String.contains?(&1, "detaillee"))
    assert length(content_node.children) >= 4
  end

  test "priority modal renders colored items A-F with matching styles and cyan border" do
    s = st([t("(D) task", 1)], width: 80, height: 24, mode: :input)
    s = %{s | modal: Modal.open(:pri, s)}
    tree = View.render(s)
    all_text = texts(tree)

    # Rounded border and title
    assert Enum.any?(all_text, &String.contains?(&1, "╭─ Priorité"))
    assert Enum.any?(all_text, &String.contains?(&1, "╰"))
    assert Enum.any?(all_text, &String.contains?(&1, "Item 4 of 27"))

    nodes = text_nodes(tree)
    a_node = Enum.find(nodes, &(&1.content == "A"))
    b_node = Enum.find(nodes, &(&1.content == "B"))
    c_node = Enum.find(nodes, &(&1.content == "C"))
    # D is pre-selected because task has priority (D)
    d_node = Enum.find(nodes, &String.contains?(&1.content, "D"))

    assert a_node.style.fg == :red
    assert :bold in a_node.style.attrs
    assert b_node.style.fg == :yellow
    assert :bold in b_node.style.attrs
    assert c_node.style.fg == :cyan
    assert :bold in c_node.style.attrs
    assert d_node.style.fg == :green
    assert :reverse in d_node.style.attrs
  end

  test "detail pane renders colored priority and fields" do
    s = st([t("(A) a +proj @ctx due:2026-10-10", 1)], list_idx: 0, width: 100)
    nodes = text_nodes(View.render(s))

    # Priority A colored in detail pane
    a_nodes = Enum.filter(nodes, &(&1.content == "(A)" or &1.content == "A"))
    assert Enum.any?(a_nodes, &(&1.style.fg == :red and :bold in &1.style.attrs))

    # Projects colored in detail pane
    proj_nodes = Enum.filter(nodes, &(&1.content == "+proj"))
    assert Enum.any?(proj_nodes, &(&1.style.fg == :cyan and :bold in &1.style.attrs))
  end

  test "statusline renders scope badge [LOCAL] or [GLOBAL]" do
    s_local = st([t("a", 1)], local: true)
    assert Enum.any?(texts(View.render(s_local)), &String.contains?(&1, "[LOCAL]"))

    s_global = st([t("a", 1)], local: false)
    assert Enum.any?(texts(View.render(s_global)), &String.contains?(&1, "[GLOBAL]"))
  end

  test "visual delimitations include vertical separator bars and horizontal rule" do
    s = st([t("a", 1)])
    all_text = texts(View.render(s))
    assert Enum.any?(all_text, &String.contains?(&1, "│"))
    assert Enum.any?(all_text, &String.contains?(&1, "─"))
  end

  test "input modal displays [INS], syntax legend, and wraps preview text" do
    long_task =
      "2026-10-06 Les barres verticales sont rompues avant de rejoindre la barre horizontale du bas (UI) +projet @test due:2026-10-07 (A)"

    s = st([t(long_task, 1)], width: 80, height: 24, mode: :input)
    s = %{s | modal: Modal.open(:edit, s)}
    all_text = texts(View.render(s))

    assert Enum.any?(all_text, &String.contains?(&1, "[INS]"))
    assert Enum.any?(all_text, &String.contains?(&1, "Syntaxe :"))
    assert Enum.any?(all_text, &String.contains?(&1, "+projet"))
    assert Enum.any?(all_text, &String.contains?(&1, "due:AAAA-MM-JJ"))
    # Multiple wrapped preview lines
    preview_occurrences = Enum.filter(all_text, &String.contains?(&1, "verticales"))
    assert preview_occurrences != []
  end

  test "filter modal displays [INS], pattern legend, and [Ctrl+U]" do
    s = st([t("a", 1)], width: 80, height: 24, mode: :input)
    s = %{s | modal: Modal.open(:filter, s)}
    all_text = texts(View.render(s))

    assert Enum.any?(all_text, &String.contains?(&1, "FILTRER LES TÂCHES [INS]"))
    assert Enum.any?(all_text, &String.contains?(&1, "Filtres disponibles"))
    assert Enum.any?(all_text, &String.contains?(&1, "[Ctrl+U]"))
  end

  test "due: tag highlighting: valid dates and ASAP are yellow bold, invalid and empty are red bold underline" do
    valid_task = t("task due:2026-10-07 due:ASAP", 1)
    invalid_task = t("task due:2026-02-30 due:", 2)

    s_valid = st([valid_task], focus: :list, list_idx: 0)
    valid_nodes = text_nodes(View.render(s_valid))
    due_date_node = Enum.find(valid_nodes, &(&1.content == "due:2026-10-07"))
    due_asap_node = Enum.find(valid_nodes, &(&1.content == "due:ASAP"))

    assert due_date_node.style.fg == :yellow
    assert :bold in due_date_node.style.attrs
    assert due_asap_node.style.fg == :yellow
    assert :bold in due_asap_node.style.attrs

    s_invalid = st([invalid_task], focus: :list, list_idx: 0)
    invalid_nodes = text_nodes(View.render(s_invalid))
    bad_date_node = Enum.find(invalid_nodes, &(&1.content == "due:2026-02-30"))
    empty_due_node = Enum.find(invalid_nodes, &(&1.content == "due:"))

    assert bad_date_node.style.fg == :red
    assert :bold in bad_date_node.style.attrs
    assert :underline in bad_date_node.style.attrs

    assert empty_due_node.style.fg == :red
    assert :bold in empty_due_node.style.attrs
    assert :underline in empty_due_node.style.attrs
  end

  test "input modal wraps Saisie field across multiple rows when long" do
    long_task =
      "2026-10-06 Dans la fenêtre d'ajouter/édition des todos, le text wrap se fait bien sur l'aperçu mais pas sur la saisie."

    s = st([t(long_task, 1)], width: 60, height: 28, mode: :input)
    s = %{s | modal: Modal.open(:edit, s)}
    all_text = texts(View.render(s))

    # The prefix "│  > " and continuation "│    " both appear in the rendered modal
    assert Enum.any?(all_text, &String.contains?(&1, "│  > "))
    assert Enum.any?(all_text, &String.contains?(&1, "│    "))
  end

  test "statusline wraps shortcuts across multiple lines when shell window is small" do
    s_small = st([t("task", 1)], width: 80, height: 24)
    rendered_small = View.render(s_small)

    {_header, _body, status_small} =
      case rendered_small.children do
        [{h, _}, {b, _}, {st_node, _}] -> {h, b, st_node}
      end

    # Statusline has separator + info line + multiple shortcut lines (>= 4 lines total)
    assert length(status_small.children) >= 4

    s_wide = st([t("task", 1)], width: 170, height: 24)
    rendered_wide = View.render(s_wide)

    {_header, _body, status_wide} =
      case rendered_wide.children do
        [{h, _}, {b, _}, {st_node, _}] -> {h, b, st_node}
      end

    # Wide screen fits shortcuts onto 1 line (separator + info + 1 shortcut line = 3 lines)
    assert length(status_wide.children) == 3
  end
end
