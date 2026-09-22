defmodule TodoTxt.Tui do
  @moduledoc "Interactive TUI — `todo --tui`. Elm app on term_ui."
  use TermUI.Elm

  alias TodoTxt.{Editor, Format, Ops, Task}
  alias TodoTxt.Tui.{Keys, Modal, State, View}
  alias TermUI.{Command, Event}
  alias TermUI.Widgets.TextInput

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
            with {:ok, tasks} <- env.io.read.(env.paths.todo),
                 {:ok, done} <- env.io.read.(env.paths.done) do
              run(%{env | tasks: tasks, done_tasks: done})
            else
              {:error, m} -> {:error, m}
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
        done2 = Enum.reject(s.done_tasks, &(&1.line == t.line))

        s2 =
          with :ok <- s.io.append.(s.paths.todo, [reopened]),
               :ok <- s.io.write.(s.paths.done, done2) do
            # Les DEUX fichiers ont changé : reload resynchronise les deux
            # miroirs (s.tasks inclus) + mtimes + clamp, au lieu de ne mettre
            # à jour que done_tasks à la main.
            reload(%{s | status: "#{t.line}: reopened"})
          else
            {:error, m} -> %{s | status: "error: " <> m}
          end

        {s2, []}
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
        {:ok, open} = Ops.delete(s.tasks, t)

        s2 =
          with :ok <- s.io.append.(s.paths.done, [t]),
               :ok <- s.io.write.(s.paths.todo, open) do
            # done.txt ET todo.txt ont changé → reload resynchronise les deux.
            reload(%{s | status: "#{t.line}: moved to done"})
          else
            {:error, m} -> %{s | status: "error: " <> m}
          end

        {s2, []}

      {:done, t} when not is_nil(t) ->
        done2 = Enum.reject(s.done_tasks, &(&1.line == t.line))

        s2 =
          with :ok <- s.io.append.(s.paths.todo, [t]),
               :ok <- s.io.write.(s.paths.done, done2) do
            reload(%{s | status: "#{t.line}: moved to todo"})
          else
            {:error, m} -> %{s | status: "error: " <> m}
          end

        {s2, []}

      _ ->
        {s, []}
    end
  end

  def update(:reload, s), do: {reload(s), []}

  # :tick (2 s, Command.interval en init) : watch externe sur les mtimes.
  # Aucun changement → no-op (même struct). Changement → reload, qui
  # rafraîchit les mtimes et clampe la sélection.
  def update(:tick, s) do
    todo_m = State.mtime(s.io, s.paths.todo)
    done_m = State.mtime(s.io, s.paths.done)

    if todo_m == s.mtimes[:todo] and done_m == s.mtimes[:done] do
      {s, []}
    else
      {reload(%{s | status: "rechargé (fichier modifié)"}), []}
    end
  end

  # Le send DOIT précéder le Command.quit() : handle_exit lit la mailbox
  # en `after 0` — le message doit déjà y être quand le runtime s'arrête.
  def update(:edit_external, s) do
    if s.caller, do: send(s.caller, {:tui_exit, :edit})
    {s, [Command.quit()]}
  end

  def update({:open_modal, action}, s) do
    needs_task = action in [:edit, :append, :prepend, :del, :pri]

    if needs_task and is_nil(State.selected_task(s)) do
      {s, []}
    else
      {%{s | mode: :input, modal: Modal.open(action, s)}, []}
    end
  end

  def update({:modal_event, %Event.Key{key: :escape}}, s), do: update(:modal_cancel, s)

  def update(
        {:modal_event, %Event.Key{key: :enter}},
        %{modal: %{widget_mod: TextInput}} = s
      ),
      do: update(:modal_submit, s)

  def update({:modal_event, ev}, %{modal: %{widget: w, widget_mod: mod}} = s) do
    case mod.handle_event(normalize_key(ev), w) do
      {:ok, w2} ->
        {%{s | modal: %{s.modal | widget: w2}}, []}

      {:ok, w2, effects} ->
        # Widget self-messages (PickList {:select, item} / :cancel) go back
        # through the root's handle_info -> update.
        Enum.each(effects || [], fn {:send, pid, msg} -> send(pid, msg) end)
        {%{s | modal: %{s.modal | widget: w2}}, []}
    end
  end

  def update(:modal_cancel, s), do: {%{s | mode: :normal, modal: nil}, []}

  def update(:modal_submit, %{modal: %{widget_mod: TextInput} = modal} = s) do
    s = %{s | mode: :normal, modal: nil}
    text = TextInput.get_value(modal.widget) |> String.trim()

    case {modal.action, text} do
      {_, ""} when modal.action != :filter ->
        {s, []}

      {:add, text} ->
        task = Ops.add(s.tasks, text, s.today)

        case s.io.append.(s.paths.todo, [task]) do
          :ok ->
            {%{s | tasks: s.tasks ++ [task], status: "#{task.line}: added"}
             |> State.refresh_mtimes()
             |> State.clamp_selection(), []}

          {:error, m} ->
            {%{s | status: "error: " <> m}, []}
        end

      {:filter, text} ->
        {%{s | filter_terms: String.split(text, ~r/\s+/, trim: true), list_idx: 0}, []}

      {:edit, text} ->
        {mutate_line(s, modal.line, &Ops.replace_text(&1, &2, text), "edited"), []}

      {:append, text} ->
        {mutate_line(s, modal.line, &Ops.append_text(&1, &2, text), "appended"), []}

      {:prepend, text} ->
        {mutate_line(s, modal.line, &Ops.prepend_text(&1, &2, text), "prepended"), []}

      _ ->
        {s, []}
    end
  end

  def update({:select, item}, %{modal: %{action: :pri, line: line}} = s) do
    s = %{s | mode: :normal, modal: nil}
    prio = if item == "(aucune)", do: nil, else: :binary.first(item)
    {mutate_line(s, line, &Ops.set_priority(&1, &2, prio), "priority"), []}
  end

  def update(:cancel, s), do: update(:modal_cancel, s)

  def update({:dialog_result, r}, %{modal: %{action: a} = m} = s)
      when r in [:yes, :confirm, :ok] do
    s = %{s | mode: :normal, modal: nil}

    case a do
      :del ->
        {mutate_line(s, m.line, &Ops.delete/2, "deleted"), []}

      :archive ->
        {open, done} = Ops.archive(s.tasks)

        s2 =
          with :ok <- if(done == [], do: :ok, else: s.io.append.(s.paths.done, done)),
               :ok <- s.io.write.(s.paths.todo, open) do
            # done.txt (append) ET todo.txt (rewrite) ont changé → reload.
            reload(%{s | status: "archived #{length(done)}"})
          else
            {:error, m} -> %{s | status: "error: " <> m}
          end

        {s2, []}

      # :help et autres infos : fermer sans action.
      _ ->
        {s, []}
    end
  end

  def update({:dialog_result, _}, s), do: {%{s | mode: :normal, modal: nil}, []}

  # Catch-all : messages inattendus (widget orphans, timers annulés) = no-op.
  def update(_, s), do: {s, []}

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
  defp mutate_line(s, nil, _op, _label), do: s

  defp mutate_line(%{view: :done} = s, line, op, label) do
    case Enum.find(s.done_tasks, &(&1.line == line)) do
      nil ->
        %{s | status: "error: task #{line} no longer exists"}

      fresh ->
        case op.(s.done_tasks, fresh) do
          {:ok, done2} ->
            case s.io.write.(s.paths.done, done2) do
              :ok ->
                %{s | done_tasks: done2, status: "#{line}: #{label}"}
                |> State.refresh_mtimes()
                |> State.clamp_selection()

              {:error, m} ->
                %{s | status: "error: " <> m}
            end

          {:error, m} ->
            %{s | status: "error: " <> m}
        end
    end
  end

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

  def view(state), do: View.render(state)
  def handle_info(msg, state), do: update(msg, state)
end
