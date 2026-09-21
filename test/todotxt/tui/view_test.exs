defmodule TodoTxt.Tui.ViewTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Parser, Tui.State, Tui.View}
  alias TermUI.Component.RenderNode

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

  test "root is a vertical stack: body fill + statusline" do
    %RenderNode{type: :stack, direction: :vertical, children: [{body, _}, {status, _}]} =
      View.render(st([t("a", 1)]))

    assert body.direction == :horizontal
    assert length(body.children) == 3
    assert %RenderNode{type: :text} = status
  end

  test "task rows carry N: raw; selected row has reverse style when list focused" do
    tree = View.render(st([t("a", 1), t("b", 2)], focus: :list, list_idx: 1))
    %RenderNode{children: [{body, _}, {_status, _}]} = tree
    %RenderNode{children: [{_sb, _}, {list, _}, {_d, _}]} = body
    sel = Enum.at(list.children, 1)
    assert %RenderNode{type: :text, content: " 2: b", style: style} = sel
    assert :reverse in style.attrs
  end

  test "agenda view renders date headers; statusline shows active filters" do
    s = st([t("s due:2026-09-25", 1)], view: :agenda)
    assert " 2026-09-25:" in texts(View.render(s))

    s = st([t("a", 1)], filter_terms: ["+p"])
    assert Enum.any?(texts(View.render(s)), &String.contains?(&1, "+p"))
  end
end
