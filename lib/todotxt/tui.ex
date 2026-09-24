defmodule TodoTxt.Tui do
  @moduledoc "Interactive TUI — `todo --tui`. Elm app on term_ui."
  use TermUI.Elm

  alias TodoTxt.{Editor, Format, Tasks}
  alias TodoTxt.Tui.{Keys, Modal, State, View}
  alias TermUI.{Command, Event}
  alias TermUI.Widgets.TextInput

  @doc "Runs the TUI; loops for external $EDITOR sessions. Returns {:ok, nil} | {:error, msg}."
  def run(env) do
    env =
      env
      |> Map.put_new(:today, Date.utc_today())
      |> Map.put_new(:io, Map.put(Tasks.default_io(), :stat, &File.stat/1))
      # --plain / COLORS=off (déjà mergé dans env.opts) + NO_COLOR/TERM
      # → rendu monochrome (attributs seuls, aucune couleur).
      |> Map.put_new(:plain, not Format.colors_enabled?(env[:opts] || %{}))
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
          :ok ->
            # L'éditeur a pu réécrire les fichiers : recharger les deux listes
            # avant de relancer, sinon env.tasks/done_tasks restent ceux
            # d'avant l'édition et la prochaine mutation écraserait ses
            # changements (refresh_mtimes neutralise en plus le watch).
            with {:ok, lists} <- Tasks.load(env.io, env.paths) do
              run(Map.merge(env, lists))
            end

          {:error, m} ->
            {:error, m}
        end
    after
      0 -> {:ok, nil}
    end
  end

  # Le runtime est déjà quitté à ce point (terminal restauré) : le port
  # :nouse_stdio d'Editor donne au fils le vrai tty. VISUAL > EDITOR > vi.
  defp edit_external(env), do: Editor.open(env.paths.todo)

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

  @typedoc """
  Pure description of an I/O step, returned by `decide/2` next to native
  `TermUI.Command`s and run in order by `run_effects/2`. After an error
  (status `"error: ..."`), the remaining I/O steps are skipped.

    * `{:persist, op, args}` — a `TodoTxt.Tasks` mutation with `s.io`;
      merges the returned list(s) and the status toast
    * `:sync` — refresh mtimes + clamp selection (single-file mutations)
    * `:reload` — re-read both files, then `:sync` (cross-file mutations)
    * `:watch` — stat both files; `:reload` only if an mtime changed
    * `{:status, msg}` / `{:send, pid, msg}`
  """
  @type io_effect ::
          {:persist, atom(), map()}
          | :sync
          | :reload
          | :watch
          | {:status, String.t()}
          | {:send, pid(), term()}

  @doc "Elm update: pure `decide/2`, then the effect interpreter."
  def update(msg, s) do
    {s2, effects} = decide(msg, s)
    run_effects(s2, effects)
  end

  @doc "Pure transition: `{state, [io_effect | TermUI.Command.t()]}`, no I/O."
  def decide({:resize, w, h}, s), do: {%{s | width: w, height: h}, []}
  def decide({:nav, d}, s), do: {State.move_cursor(s, d), []}

  def decide(:focus_next, s),
    do: {%{s | focus: if(s.focus == :sidebar, do: :list, else: :sidebar)}, []}

  def decide(:focus_sidebar, s), do: {%{s | focus: :sidebar}, []}
  def decide(:focus_list, s), do: {%{s | focus: :list}, []}

  def decide(:activate, %{focus: :sidebar} = s),
    do: {State.activate_sidebar(s) |> Map.put(:focus, :list), []}

  def decide(:activate, s), do: {s, []}

  def decide(:clear_filter, s), do: {%{s | filter_terms: [], list_idx: 0}, []}
  def decide(:quit, s), do: {s, [Command.quit()]}

  # En vue :done, la sélection vient de done_tasks — done.txt est positionnel,
  # ses numéros de ligne collisionnent avec todo.txt : on ne touche PAS à
  # s.tasks. Réouverture = append à todo.txt puis réécriture de done.txt ;
  # les DEUX fichiers changent → :reload resynchronise les deux miroirs.
  def decide(:toggle_done, %{view: :done} = s) do
    case State.selected_task(s) do
      nil -> {s, []}
      t -> {s, [{:persist, :reopen, %{task: t}}, :reload]}
    end
  end

  def decide(:toggle_done, s) do
    case State.selected_task(s) do
      nil -> {s, []}
      %{done: true} = t -> {s, [{:persist, :uncomplete, %{task: t}}, :sync]}
      # Le recur rejoint la liste réécrite (fin de fichier, comme le CLI).
      t -> {s, [{:persist, :complete, %{task: t}}, :sync]}
    end
  end

  def decide(:move, s) do
    case {s.view, State.selected_task(s)} do
      {view, t} when view in [:todo, :done] and not is_nil(t) ->
        {s, [{:persist, :move, %{from: view, task: t}}, :reload]}

      _ ->
        {s, []}
    end
  end

  def decide(:reload, s), do: {s, [:reload]}

  # :tick (2 s, Command.interval en init) : watch externe sur les mtimes.
  # Aucun changement → no-op (même struct). Changement → reload, qui
  # rafraîchit les mtimes et clampe la sélection.
  def decide(:tick, s), do: {s, [:watch]}

  # Le send DOIT précéder le Command.quit() : handle_exit lit la mailbox
  # en `after 0` — le message doit déjà y être quand le runtime s'arrête
  # (les io_effect s'exécutent dans update/2, avant le retour au runtime).
  def decide(:edit_external, s) do
    notify = if s.caller, do: [{:send, s.caller, {:tui_exit, :edit}}], else: []
    {s, notify ++ [Command.quit()]}
  end

  def decide({:open_modal, action}, s) do
    needs_task = action in [:edit, :append, :prepend, :del, :pri]

    if needs_task and is_nil(State.selected_task(s)) do
      {s, []}
    else
      {%{s | mode: :input, modal: Modal.open(action, s)}, []}
    end
  end

  def decide({:modal_event, %Event.Key{key: :escape}}, s), do: decide(:modal_cancel, s)

  def decide(
        {:modal_event, %Event.Key{key: :enter}},
        %{modal: %{widget_mod: TextInput}} = s
      ),
      do: decide(:modal_submit, s)

  def decide({:modal_event, ev}, %{modal: %{widget: w, widget_mod: mod}} = s) do
    case mod.handle_event(normalize_key(ev), w) do
      {:ok, w2} ->
        {%{s | modal: %{s.modal | widget: w2}}, []}

      {:ok, w2, effects} ->
        # Widget self-messages (PickList {:select, item} / :cancel) are
        # {:send, pid, msg} effects; they come back through the root's
        # handle_info -> update.
        {%{s | modal: %{s.modal | widget: w2}}, effects || []}
    end
  end

  def decide(:modal_cancel, s), do: {%{s | mode: :normal, modal: nil}, []}

  def decide(:modal_submit, %{modal: %{widget_mod: TextInput} = modal} = s) do
    s = %{s | mode: :normal, modal: nil}
    text = TextInput.get_value(modal.widget) |> String.trim()

    case {modal.action, text} do
      {_, ""} when modal.action != :filter ->
        {s, []}

      {:add, text} ->
        {s, [{:persist, :add, %{text: text}}, :sync]}

      {:filter, text} ->
        {%{s | filter_terms: String.split(text, ~r/\s+/, trim: true), list_idx: 0}, []}

      {:edit, text} ->
        mutate_line(s, modal.line, {:replace_text, text}, "edited")

      {:append, text} ->
        mutate_line(s, modal.line, {:append_text, text}, "appended")

      {:prepend, text} ->
        mutate_line(s, modal.line, {:prepend_text, text}, "prepended")

      _ ->
        {s, []}
    end
  end

  def decide({:select, item}, %{modal: %{action: :pri, line: line}} = s) do
    s = %{s | mode: :normal, modal: nil}
    prio = if item == "(aucune)", do: nil, else: :binary.first(item)
    mutate_line(s, line, {:set_priority, prio}, "priority")
  end

  def decide(:cancel, s), do: decide(:modal_cancel, s)

  def decide({:dialog_result, r}, %{modal: %{action: a} = m} = s)
      when r in [:yes, :confirm, :ok] do
    s = %{s | mode: :normal, modal: nil}

    case a do
      :del -> mutate_line(s, m.line, :delete, "deleted")
      # done.txt (append) ET todo.txt (rewrite) changent → :reload.
      :archive -> {s, [{:persist, :archive, %{}}, :reload]}
      # :help et autres infos : fermer sans action.
      _ -> {s, []}
    end
  end

  def decide({:dialog_result, _}, s), do: {%{s | mode: :normal, modal: nil}, []}

  # Catch-all : messages inattendus (widget orphans, timers annulés) = no-op.
  def decide(_, s), do: {s, []}

  # Printable keys from the real parser carry `key` and `char`; synthetic
  # events (tests) may only set `key` — fill `char` so widgets see input.
  # Modified keys (Ctrl+A-Z reach us as key: "a", char: nil, modifiers: [:ctrl])
  # must NOT get char — they are commands, not text.
  defp normalize_key(%Event.Key{key: k, char: nil, modifiers: []} = ev) when is_binary(k),
    do: %{ev | char: k}

  defp normalize_key(ev), do: ev

  # Re-fetch by `line` : la tâche a pu disparaître via un reload externe
  # pendant que la modale était ouverte (review focus 1). En vue :done,
  # l'op s'applique à done_tasks/done.txt — ses numéros de ligne sont
  # positionnels et collisionnent avec todo.txt.
  defp mutate_line(s, nil, _op, _label), do: {s, []}

  defp mutate_line(s, line, op, label) do
    list = if s.view == :done, do: :done, else: :todo

    case Enum.find(list_tasks(s, list), &(&1.line == line)) do
      nil ->
        {%{s | status: "error: task #{line} no longer exists"}, []}

      fresh ->
        {s, [{:persist, :edit, %{list: list, task: fresh, op: op, label: label}}, :sync]}
    end
  end

  defp list_tasks(s, :todo), do: s.tasks
  defp list_tasks(s, :done), do: s.done_tasks

  defp put_list(s, :todo, ts), do: %{s | tasks: ts}
  defp put_list(s, :done, ts), do: %{s | done_tasks: ts}

  # --- Effect interpreter (impure): every mutation goes through TodoTxt.Tasks ---

  defp run_effects(s, effects) do
    {s, cmds, _} =
      Enum.reduce(effects, {s, [], :ok}, fn
        %Command{} = cmd, {s, cmds, st} ->
          {s, [cmd | cmds], st}

        _eff, {s, cmds, :halt} ->
          {s, cmds, :halt}

        eff, {s, cmds, :ok} ->
          case run_effect(eff, s) do
            {:ok, s2} -> {s2, cmds, :ok}
            {:error, m} -> {%{s | status: "error: " <> m}, cmds, :halt}
          end
      end)

    {s, Enum.reverse(cmds)}
  end

  defp run_effect({:persist, op, args}, s) do
    with {:ok, r} <- persist(op, args, s), do: {:ok, merge(op, args, r, s)}
  end

  defp run_effect(:sync, s), do: {:ok, s |> State.refresh_mtimes() |> State.clamp_selection()}

  defp run_effect(:reload, s) do
    with {:ok, %{tasks: tasks, done_tasks: done}} <- Tasks.load(s.io, s.paths) do
      run_effect(:sync, %{s | tasks: tasks, done_tasks: done})
    end
  end

  defp run_effect(:watch, s) do
    todo_m = State.mtime(s.io, s.paths.todo)
    done_m = State.mtime(s.io, s.paths.done)

    if todo_m == s.mtimes[:todo] and done_m == s.mtimes[:done],
      do: {:ok, s},
      else: run_effect(:reload, %{s | status: "rechargé (fichier modifié)"})
  end

  defp run_effect({:status, msg}, s), do: {:ok, %{s | status: msg}}

  defp run_effect({:send, pid, msg}, s) do
    send(pid, msg)
    {:ok, s}
  end

  defp persist(:complete, %{task: t}, s), do: Tasks.complete(s.io, s.paths, s.tasks, t, s.today)
  defp persist(:uncomplete, %{task: t}, s), do: Tasks.uncomplete(s.io, s.paths, s.tasks, t)
  defp persist(:reopen, %{task: t}, s), do: Tasks.reopen(s.io, s.paths, s.done_tasks, t)

  defp persist(:move, %{from: :todo, task: t}, s),
    do: Tasks.move(s.io, s.paths.todo, s.paths.done, s.tasks, t)

  defp persist(:move, %{from: :done, task: t}, s),
    do: Tasks.move(s.io, s.paths.done, s.paths.todo, s.done_tasks, t)

  defp persist(:archive, _, s), do: Tasks.archive(s.io, s.paths, s.tasks)
  defp persist(:add, %{text: text}, s), do: Tasks.add(s.io, s.paths, s.tasks, text, s.today)

  defp persist(:edit, %{list: list, task: t, op: op}, s) do
    path = if list == :done, do: s.paths.done, else: s.paths.todo
    edit(s.io, path, list_tasks(s, list), t, op)
  end

  defp edit(io, path, ts, t, :delete), do: Tasks.delete(io, path, ts, t)
  defp edit(io, path, ts, t, {:set_priority, p}), do: Tasks.set_priority(io, path, ts, t, p)
  defp edit(io, path, ts, t, {:replace_text, x}), do: Tasks.replace_text(io, path, ts, t, x)
  defp edit(io, path, ts, t, {:append_text, x}), do: Tasks.append_text(io, path, ts, t, x)
  defp edit(io, path, ts, t, {:prepend_text, x}), do: Tasks.prepend_text(io, path, ts, t, x)

  defp merge(:complete, %{task: t}, r, s), do: %{s | tasks: r.tasks, status: "#{t.line}: done"}

  defp merge(:uncomplete, %{task: t}, r, s),
    do: %{s | tasks: r.tasks, status: "#{t.line}: reopened"}

  defp merge(:reopen, %{task: t}, r, s),
    do: %{s | done_tasks: r.done_tasks, status: "#{t.line}: reopened"}

  defp merge(:move, %{from: :todo, task: t}, r, s),
    do: %{s | tasks: r.tasks, status: "#{t.line}: moved to done"}

  defp merge(:move, %{from: :done, task: t}, r, s),
    do: %{s | done_tasks: r.tasks, status: "#{t.line}: moved to todo"}

  defp merge(:archive, _, r, s), do: %{s | tasks: r.tasks, status: "archived #{r.count}"}
  defp merge(:add, _, r, s), do: %{s | tasks: r.tasks, status: "#{r.task.line}: added"}

  defp merge(:edit, %{list: list, task: t, label: label}, r, s),
    do: put_list(s, list, r.tasks) |> Map.put(:status, "#{t.line}: #{label}")

  def view(state), do: View.render(state)
  def handle_info(msg, state), do: update(msg, state)
end
