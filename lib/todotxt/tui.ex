defmodule TodoTxt.Tui do
  @moduledoc "Interactive TUI — `todo --tui`. Elm app on term_ui."
  use TermUI.Elm

  alias TodoTxt.{Ops, Task}
  alias TodoTxt.Tui.{Keys, State}
  alias TermUI.{Command, Event}

  @doc "Runs the TUI; loops for external $EDITOR sessions. Returns {:ok, nil} | {:error, msg}."
  def run(env) do
    env =
      env
      |> Map.put_new(:today, Date.utc_today())
      |> Map.put_new(:io, %{
        read: &TodoTxt.Store.read/1,
        write: &TodoTxt.Store.write/2,
        append: &TodoTxt.Store.append/2,
        stat: &File.stat/1
      })
      |> Map.put(:caller, self())

    # TermUI.Runtime.run/1 returns :ok | {:error, term}; the test seam may
    # also return {:ok, _} (TermUI.App.run/2's shape) — both mean clean exit.
    runner = env[:runner] || fn e -> TermUI.Runtime.run(root: __MODULE__, env: e) end

    case runner.(env) do
      :ok -> handle_exit(env)
      {:ok, _} -> handle_exit(env)
      {:error, m} -> {:error, m}
    end
  end

  defp handle_exit(env) do
    # Selective receive: only consume the TUI's own edit-request message;
    # unrelated mailbox messages must be left for the caller.
    receive do
      {:tui_exit, :edit} ->
        case edit_external(env) do
          :ok -> run(env)
          {:error, m} -> {:error, m}
        end
    after
      0 -> {:ok, nil}
    end
  end

  defp edit_external(env) do
    editor = System.get_env("EDITOR")

    if is_nil(editor) do
      {:error, "$EDITOR not set"}
    else
      try do
        case System.cmd(editor, [env.paths.todo], into: IO.stream(:stdio, :line)) do
          {_, 0} -> :ok
          {_, code} -> {:error, "editor exited #{code}"}
        end
      rescue
        ErlangError -> {:error, "editor not found: #{editor}"}
      end
    end
  end

  # --- Elm callbacks ---
  def init(opts) do
    env = Keyword.fetch!(opts, :env)
    # Seed mtimes : sinon le 1er :tick (2 s) déclenche un reload parasite.
    state = State.new(env) |> State.refresh_mtimes()
    {:ok, state, [Command.interval(2_000, :tick)]}
  end

  def event_to_msg(%Event.Resize{width: w, height: h}, _s), do: {:msg, {:resize, w, h}}
  def event_to_msg(%Event.Key{} = ev, state), do: Keys.msg(ev, state.mode) |> wrap()
  def event_to_msg(_, _), do: :ignore

  defp wrap(:ignore), do: :ignore
  defp wrap(msg), do: {:msg, msg}

  def update({:resize, w, h}, s), do: {%{s | width: w, height: h}, []}
  def update({:nav, d}, s), do: {State.move_cursor(s, d), []}

  def update(:focus_next, s),
    do: {%{s | focus: if(s.focus == :sidebar, do: :list, else: :sidebar)}, []}

  def update(:focus_sidebar, s), do: {%{s | focus: :sidebar}, []}
  def update(:focus_list, s), do: {%{s | focus: :list}, []}

  def update(:activate, %{focus: :sidebar} = s),
    do: {State.activate_sidebar(s) |> Map.put(:focus, :list), []}

  def update(:activate, s), do: {s, []}

  def update(:clear_filter, s), do: {%{s | filter_terms: [], list_idx: 0}, []}
  def update(:quit, s), do: {s, [Command.quit()]}

  # En vue :done, la sélection vient de done_tasks — done.txt est positionnel,
  # ses numéros de ligne collisionnent avec todo.txt : on ne touche PAS à
  # s.tasks. On réouvre, on append à todo.txt, on réécrit done.txt sans elle.
  def update(:toggle_done, %{view: :done} = s) do
    case State.selected_task(s) do
      nil ->
        {s, []}

      t ->
        reopened = Task.uncomplete(t)
        :ok = s.io.append.(s.paths.todo, [reopened])
        done2 = Enum.reject(s.done_tasks, &(&1.line == t.line))
        :ok = s.io.write.(s.paths.done, done2)

        {%{s | done_tasks: done2, status: "#{t.line}: reopened"}
         |> State.refresh_mtimes()
         |> State.clamp_selection(), []}
    end
  end

  def update(:toggle_done, s) do
    case State.selected_task(s) do
      nil ->
        {s, []}

      %{done: true} = t ->
        {State.mutate(s, Ops.uncomplete(s.tasks, t), "#{t.line}: reopened"), []}

      t ->
        case Ops.complete(s.tasks, t, s.today) do
          {:ok, ts, recur} ->
            # Le recur rejoint la liste réécrite (fin de fichier, comme le CLI).
            ts = if recur, do: ts ++ [%{recur | line: Ops.next_line(s.tasks)}], else: ts
            {State.mutate(s, {:ok, ts}, "#{t.line}: done"), []}

          {:error, m} ->
            {%{s | status: "error: " <> m}, []}
        end
    end
  end

  def update(:move, s) do
    case {s.view, State.selected_task(s)} do
      {:todo, t} when not is_nil(t) ->
        :ok = s.io.append.(s.paths.done, [t])
        {State.mutate(s, Ops.delete(s.tasks, t), "#{t.line}: moved to done"), []}

      {:done, t} when not is_nil(t) ->
        :ok = s.io.append.(s.paths.todo, [t])
        done2 = Enum.reject(s.done_tasks, &(&1.line == t.line))
        :ok = s.io.write.(s.paths.done, done2)

        {%{s | done_tasks: done2, status: "#{t.line}: moved to todo"}
         |> State.refresh_mtimes()
         |> State.clamp_selection(), []}

      _ ->
        {s, []}
    end
  end

  def update(:reload, s), do: {reload(s), []}

  # Scaffold de modal (Task 7 ajoute les vrais widgets) : map simple
  # %{action:, line:} — pas de widget/widget_mod.
  def update({:open_modal, action}, s) do
    if modal_needs_task?(action) and is_nil(State.selected_task(s)) do
      {s, []}
    else
      line =
        case State.selected_task(s) do
          nil -> nil
          t -> t.line
        end

      {%{s | mode: :input, modal: %{action: action, line: line}}, []}
    end
  end

  def update({:dialog_result, r}, %{modal: %{action: :del, line: line}} = s)
      when r in [:yes, :confirm, :ok] do
    s = %{s | mode: :normal, modal: nil}
    {mutate_line(s, line, &Ops.delete/2, "deleted"), []}
  end

  def update({:dialog_result, _}, s), do: {%{s | mode: :normal, modal: nil}, []}

  # Catch-all : messages inattendus (widget orphans, timers annulés) = no-op.
  def update(_, s), do: {s, []}

  defp modal_needs_task?(action), do: action in [:del]

  # Re-fetch the task by `line` (the list may have changed under the modal),
  # then apply `op` through State.mutate — file stays source of truth.
  defp mutate_line(s, line, op, label) do
    case Enum.find(s.tasks, &(&1.line == line)) do
      nil -> %{s | status: "error: task #{line} no longer exists"}
      fresh -> State.mutate(s, op.(s.tasks, fresh), "#{line}: #{label}")
    end
  end

  defp reload(s) do
    with {:ok, tasks} <- s.io.read.(s.paths.todo),
         {:ok, done} <- s.io.read.(s.paths.done) do
      %{s | tasks: tasks, done_tasks: done}
      |> State.refresh_mtimes()
      |> State.clamp_selection()
    else
      {:error, m} -> %{s | status: "error: " <> m}
    end
  end

  def view(_), do: text("todo --tui")
  def handle_info(msg, state), do: update(msg, state)
end
