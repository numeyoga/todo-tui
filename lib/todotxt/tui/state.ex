defmodule TodoTxt.Tui.State do
  @moduledoc "Pure TUI model: cursor, filters, views, sidebar. No rendering."

  alias TodoTxt.{Ops, Query, Tasks}

  defstruct paths: nil,
            today: nil,
            now: nil,
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
            plain: false,
            io: nil,
            opts: %{},
            local: false,
            show_hidden: false

  def new(env) do
    opts = env[:opts] || %{}
    local = opts[:local] || env[:local] || false
    width = env[:width] || 80
    height = env[:height] || 24

    %__MODULE__{
      paths: Map.get(env, :paths),
      today: Map.get(env, :today),
      now: Map.get(env, :now),
      tasks: Map.get(env, :tasks, []),
      done_tasks: Map.get(env, :done_tasks, []),
      caller: Map.get(env, :caller),
      plain: env[:plain] || false,
      io: Map.get(env, :io),
      mtimes: env[:mtimes] || %{},
      opts: opts,
      local: local,
      show_hidden: env[:show_hidden] || false,
      width: width,
      height: height
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
  def rows(%{focus: :sidebar} = s) do
    case Enum.at(sidebar_entries(s), s.sidebar_idx) do
      {:all, _} ->
        rows_for(%{s | view: :todo, filter_terms: []})

      {kind, _, term} when kind in [:project, :context] ->
        rows_for(%{s | view: :todo, filter_terms: [term]})

      {:view, _, v} ->
        rows_for(%{s | view: v, filter_terms: []})

      _ ->
        rows_for(s)
    end
  end

  def rows(s), do: rows_for(s)

  defp rows_for(%{view: :todo} = s) do
    s.tasks
    |> Query.visible(s.today, show_hidden: s.show_hidden)
    |> Query.filter(s.filter_terms)
    |> Query.sort()
    |> Enum.map(&{:task, &1})
  end

  defp rows_for(%{view: :done} = s) do
    s.done_tasks
    |> Enum.sort_by(& &1.line, :desc)
    |> Enum.map(&{:task, &1})
  end

  defp rows_for(%{view: :agenda} = s) do
    {groups, thresholds} = Ops.agenda(s.tasks, s.today)

    Enum.flat_map(groups, fn {d, ts} ->
      [{:header, "#{d}:"}] ++ Enum.map(Query.sort(ts), &{:task, &1})
    end) ++
      if thresholds == [],
        do: [],
        else: [{:header, "THRESHOLDS:"}] ++ Enum.map(thresholds, &{:task, &1})
  end

  defp rows_for(s), do: rows_for(Map.put(s, :view, :todo))

  def selected_task(s) do
    case Enum.at(task_rows(s), s.list_idx) do
      {:task, t} -> t
      _ -> nil
    end
  end

  defp task_rows(s), do: Enum.filter(rows(s), &match?({:task, _}, &1))

  # Cursor movement clamps into range. The list cursor indexes task rows
  # only, so :header rows are naturally skipped; the sidebar cursor skips
  # non-selectable :header rows and immediately updates the central pane.
  def move_cursor(%{focus: :sidebar} = s, d) do
    entries = sidebar_entries(s)
    new_idx = next_selectable_sidebar_idx(entries, s.sidebar_idx, d)
    %{s | sidebar_idx: new_idx, list_idx: 0}
  end

  def move_cursor(s, d) do
    max = max(length(task_rows(s)) - 1, 0)
    %{s | list_idx: (s.list_idx + d) |> max(0) |> min(max)}
  end

  defp next_selectable_sidebar_idx(entries, current_idx, d) do
    total = length(entries)

    if total == 0 do
      0
    else
      step = if d >= 0, do: 1, else: -1
      find_selectable(entries, current_idx + step, step, total, current_idx)
    end
  end

  defp find_selectable(_entries, target, _step, total, fallback)
       when target < 0 or target >= total do
    fallback
  end

  defp find_selectable(entries, target, step, total, fallback) do
    case Enum.at(entries, target) do
      {:header, _} ->
        find_selectable(entries, target + step, step, total, fallback)

      nil ->
        fallback

      _other ->
        target
    end
  end

  @doc "Clamp list_idx after the task set changed (reload/mutation)."
  def clamp_selection(s), do: move_cursor(%{s | list_idx: s.list_idx}, 0)

  @doc "Selects the task by line number in the current visible task rows, or clamps selection."
  def select_task_by_line(s, target_line) when is_integer(target_line) do
    rows = task_rows(s)

    case Enum.find_index(rows, fn {:task, t} -> t.line == target_line end) do
      nil -> clamp_selection(s)
      idx -> %{s | list_idx: idx}
    end
  end

  def select_task_by_line(s, _), do: clamp_selection(s)

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

  @doc "Apply an Op result to todo.txt via `Tasks.persist/3` (s.io), refresh mtimes, clamp, status."
  def mutate(s, op_result, toast) do
    case Tasks.persist(s.io, s.paths.todo, op_result) do
      {:ok, %{tasks: tasks2}} ->
        %{s | tasks: tasks2, status: toast} |> refresh_mtimes() |> clamp_selection()

      {:error, m} ->
        %{s | status: "error: " <> m}
    end
  end
end
