defmodule TodoTxt.Tui.State do
  @moduledoc "Pure TUI model: cursor, filters, views, sidebar. No rendering."

  alias TodoTxt.{Ops, Query}

  defstruct paths: nil,
            today: nil,
            tasks: [],
            done_tasks: [],
            view: :todo,
            focus: :list,
            sidebar_idx: 0,
            list_idx: 0,
            filter_terms: [],
            mode: :normal,
            modal: nil,
            toasts: [],
            mtimes: %{},
            status: nil,
            width: 80,
            height: 24,
            caller: nil,
            io: nil

  def new(env) do
    %__MODULE__{
      paths: env.paths,
      today: env.today,
      tasks: env.tasks || [],
      done_tasks: env.done_tasks || [],
      caller: env.caller,
      io: env.io,
      mtimes: env[:mtimes] || %{}
    }
  end

  def sidebar_entries(%{tasks: tasks}) do
    projects = tasks |> Enum.flat_map(& &1.projects) |> frequencies("+")
    contexts = tasks |> Enum.flat_map(& &1.contexts) |> frequencies("@")

    [{:all, "Toutes"}, {:header, "── Projets ──"}] ++
      Enum.map(projects, fn {p, n} -> {:project, "#{p} (#{n})", p} end) ++
      [{:header, "── Contextes ──"}] ++
      Enum.map(contexts, fn {c, n} -> {:context, "#{c} (#{n})", c} end) ++
      [{:header, "── Vues ──"}, {:view, "Agenda", :agenda}, {:view, "Done", :done}]
  end

  defp frequencies(list, _prefix),
    do: list |> Enum.frequencies() |> Enum.sort_by(fn {k, _} -> k end)

  @doc "Rows of the central pane: {:task, t} or section {:header, label}."
  def rows(%{view: :todo} = s) do
    s.tasks
    |> Query.visible(s.today)
    |> Query.filter(s.filter_terms)
    |> Query.sort()
    |> Enum.map(&{:task, &1})
  end

  def rows(%{view: :done} = s) do
    s.done_tasks
    |> Enum.sort_by(& &1.line, :desc)
    |> Enum.map(&{:task, &1})
  end

  def rows(%{view: :agenda} = s) do
    {groups, thresholds} = Ops.agenda(s.tasks, s.today)

    Enum.flat_map(groups, fn {d, ts} ->
      [{:header, "#{d}:"}] ++ Enum.map(Query.sort(ts), &{:task, &1})
    end) ++
      if thresholds == [],
        do: [],
        else: [{:header, "THRESHOLDS:"}] ++ Enum.map(thresholds, &{:task, &1})
  end

  def selected_task(s) do
    case Enum.at(task_rows(s), s.list_idx) do
      {:task, t} -> t
      _ -> nil
    end
  end

  defp task_rows(s), do: Enum.filter(rows(s), &match?({:task, _}, &1))

  # Cursor movement clamps into range. The list cursor indexes task rows
  # only, so :header rows are naturally skipped; the sidebar cursor indexes
  # all entries (headers included) — the brief's "saute les :header" applies
  # to the list only.
  def move_cursor(%{focus: :sidebar} = s, d) do
    max = length(sidebar_entries(s)) - 1
    %{s | sidebar_idx: (s.sidebar_idx + d) |> max(0) |> min(max)}
  end

  def move_cursor(s, d) do
    max = max(length(task_rows(s)) - 1, 0)
    %{s | list_idx: (s.list_idx + d) |> max(0) |> min(max)}
  end

  @doc "Clamp list_idx after the task set changed (reload/mutation)."
  def clamp_selection(s), do: move_cursor(%{s | list_idx: s.list_idx}, 0)

  def activate_sidebar(s) do
    case Enum.at(sidebar_entries(s), s.sidebar_idx) do
      {:all, _} ->
        %{s | view: :todo, filter_terms: [], list_idx: 0}

      {kind, _, term} when kind in [:project, :context] ->
        terms =
          if term in s.filter_terms, do: s.filter_terms -- [term], else: [term | s.filter_terms]

        %{s | view: :todo, filter_terms: terms, list_idx: 0}

      {:view, _, v} ->
        %{s | view: v, list_idx: 0}

      _ ->
        s
    end
  end

  def counts(s),
    do: %{open: Enum.count(s.tasks, &(not &1.done)), done: Enum.count(s.tasks, & &1.done)}

  @doc "File mtime via the injected io.stat, nil when unavailable."
  def mtime(io, path) do
    case io.stat.(path) do
      {:ok, st} -> st.mtime
      _ -> nil
    end
  end

  def refresh_mtimes(s) do
    %{s | mtimes: %{todo: mtime(s.io, s.paths.todo), done: mtime(s.io, s.paths.done)}}
  end
end
