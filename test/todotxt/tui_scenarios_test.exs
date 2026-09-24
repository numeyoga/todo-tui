defmodule TodoTxt.TuiScenariosTest do
  @moduledoc """
  Scénarios interactifs du TUI : séquences réalistes de `Tui.update/2`
  (via `event_to_msg/2` pour le clavier) sur un `io` factice. Les
  mutations cross-fichier (:reload) reçoivent un `io.read` qui renvoie
  l'état cohérent des fichiers après écriture.
  """
  use ExUnit.Case, async: true

  alias TermUI.Event
  alias TermUI.Widgets.TextInput
  alias TodoTxt.{Parser, Tui, Tui.State}

  defp state(tasks, opts \\ []) do
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

  defp fake_io do
    %{
      read: fn _ -> {:ok, []} end,
      write: fn _, _ -> :ok end,
      append: fn _, _ -> :ok end,
      stat: fn _ -> {:error, :enoent} end
    }
  end

  defp t(raw, line), do: Parser.parse(raw, line)

  # io qui journalise chaque write/append vers le process de test.
  defp recording_io(pid, overrides \\ %{}) do
    Map.merge(
      %{
        fake_io()
        | write: fn p, ts -> send(pid, {:write, p, ts}) && :ok end,
          append: fn p, ts -> send(pid, {:append, p, ts}) && :ok end
      },
      overrides
    )
  end

  # Envoie une touche en mode normal et applique le message obtenu.
  defp key(s, k) do
    case Tui.event_to_msg(Event.key(k), s) do
      {:msg, msg} ->
        {s2, _cmds} = Tui.update(msg, s)
        s2

      :ignore ->
        s
    end
  end

  # Tape une chaîne caractère par caractère dans la modale courante.
  defp type(s, text) do
    text
    |> String.graphemes()
    |> Enum.reduce(s, fn ch, acc ->
      {:msg, {:modal_event, ev}} = Tui.event_to_msg(Event.key(ch), acc)
      {acc2, []} = Tui.update({:modal_event, ev}, acc)
      acc2
    end)
  end

  defp selected(s), do: State.selected_task(s)

  defp gtd_tasks do
    [
      t("(A) 2026-09-10 rendre rapport +boulot @bureau due:2026-09-19", 1),
      t("2026-09-10 acheter pain +courses @magasin due:2026-09-24", 2),
      t("(C) 2026-09-10 relire specs +boulot @bureau", 3),
      t("(B) 2026-09-10 appeler mamie +perso @téléphone", 4),
      t("2026-09-10 plus tard +perso t:2027-01-01", 5)
    ]
  end

  # ---------------------------------------------------------------------
  # 1. Navigation + filtre
  # ---------------------------------------------------------------------

  test "navigation j/k/flèches sur la liste triée, puis filtre via modale" do
    s = state(gtd_tasks())

    # Ordre affiché : prio A(1), B(4), C(3), puis sans prio par ligne (2) ;
    # la ligne 5 (t: futur) est masquée.
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [1, 4, 3, 2]
    assert selected(s).line == 1

    s = s |> key("j") |> key("j")
    assert s.list_idx == 2 and selected(s).line == 3

    s = key(s, :down)
    assert selected(s).line == 2
    # Clamp en bas de liste
    s = s |> key("j") |> key("j")
    assert s.list_idx == 3 and selected(s).line == 2

    s = key(s, :up)
    assert selected(s).line == 3
    s = s |> key("k") |> key("k") |> key("k") |> key("k")
    assert s.list_idx == 0

    # `/` ouvre la modale filtre ; taper un projet puis Enter
    s = s |> key("j") |> key("j")
    assert {:msg, {:open_modal, :filter}} = Tui.event_to_msg(Event.key("/"), s)
    {s, []} = Tui.update({:open_modal, :filter}, s)
    assert s.mode == :input and s.modal.action == :filter
    assert TextInput.get_value(s.modal.widget) == ""

    # En mode :input, `j` est routé à la modale, pas à la navigation
    assert {:msg, {:modal_event, %Event.Key{key: "j"}}} = Tui.event_to_msg(Event.key("j"), s)

    s = type(s, "+boulot")
    assert TextInput.get_value(s.modal.widget) == "+boulot"
    {:msg, {:modal_event, enter}} = Tui.event_to_msg(Event.key(:enter), s)
    {s, []} = Tui.update({:modal_event, enter}, s)

    assert s.mode == :normal and s.modal == nil
    assert s.filter_terms == ["+boulot"]
    # Le curseur est remis à 0 et la liste ne contient que +boulot
    assert s.list_idx == 0
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [1, 3]

    # Filtre multi-termes (AND) : projet + contexte + texte libre
    {s, []} = Tui.update({:open_modal, :filter}, s)
    # La modale est pré-remplie avec le filtre courant
    # (curseur du TextInput en début de champ → End avant de compléter)
    assert TextInput.get_value(s.modal.widget) == "+boulot"
    {s, []} = Tui.update({:modal_event, Event.key(:end)}, s)
    s = type(s, " @bureau SPECS")
    {s, []} = Tui.update(:modal_submit, s)
    assert s.filter_terms == ["+boulot", "@bureau", "SPECS"]
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [3]

    # Filtre sans résultat : pas de sélection, nav est un no-op sûr
    {s, []} = Tui.update({:open_modal, :filter}, s)
    {s, []} = Tui.update(:modal_cancel, s)
    assert s.filter_terms == ["+boulot", "@bureau", "SPECS"]
    s2 = %{s | filter_terms: ["+inexistant"]}
    assert State.rows(s2) == [] and selected(s2) == nil
    assert key(s2, "j").list_idx == 0

    # Esc en mode normal efface le filtre
    assert {:msg, :clear_filter} = Tui.event_to_msg(Event.key(:escape), s)
    s = key(s, :escape)
    assert s.filter_terms == [] and length(State.rows(s)) == 4

    # Filtre soumis vide = efface aussi (pré-rempli "x" → Delete pour vider)
    {s, []} = Tui.update({:open_modal, :filter}, %{s | filter_terms: ["x"]})
    assert TextInput.get_value(s.modal.widget) == "x"
    {s, []} = Tui.update({:modal_event, Event.key(:delete)}, s)
    assert TextInput.get_value(s.modal.widget) == ""
    {s, []} = Tui.update(:modal_submit, s)
    assert s.filter_terms == []
  end

  test "sidebar : Tab/h/l changent le focus, Enter active projet/contexte/vue" do
    s = state(gtd_tasks())
    assert s.focus == :list

    s = key(s, :tab)
    assert s.focus == :sidebar
    s = key(s, "l")
    assert s.focus == :list
    s = key(s, "h")
    assert s.focus == :sidebar

    entries = State.sidebar_entries(s)
    # Projets/contextes comptés (la tâche 5 masquée compte quand même)
    assert {:project, "+boulot (2)", "+boulot"} in entries
    assert {:project, "+perso (2)", "+perso"} in entries
    assert {:context, "@bureau (2)", "@bureau"} in entries

    # j en focus sidebar déplace sidebar_idx, pas list_idx
    idx = Enum.find_index(entries, &match?({:project, _, "+perso"}, &1))
    s = Enum.reduce(1..idx, s, fn _, acc -> key(acc, "j") end)
    assert s.sidebar_idx == idx and s.list_idx == 0

    # Enter : filtre +perso, focus revient à la liste
    s = key(s, :enter)
    assert s.focus == :list and s.filter_terms == ["+perso"]
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [4]

    # Ré-activer le même projet le retire (toggle)
    s = key(s, "h") |> key(:enter)
    assert s.filter_terms == []

    # Vue Done via la sidebar
    s = key(s, "h")
    done_idx = Enum.find_index(entries, &match?({:view, _, :done}, &1))
    s = %{s | sidebar_idx: done_idx} |> key(:enter)
    assert s.view == :done and s.list_idx == 0
    assert State.rows(s) == []

    # Vue Agenda : headers de date + tâche due dans 14 jours
    agenda_idx = Enum.find_index(entries, &match?({:view, _, :agenda}, &1))
    s = %{s | focus: :sidebar, sidebar_idx: agenda_idx} |> key(:enter)
    assert s.view == :agenda
    assert State.rows(s) == [{:header, "2026-09-24:"}, {:task, Enum.at(gtd_tasks(), 1)}]
    # Le curseur saute les headers : la sélection est directement la tâche
    assert selected(s).line == 2

    # "Toutes" remet la vue todo
    s = %{s | focus: :sidebar, sidebar_idx: 0} |> key(:enter)
    assert s.view == :todo
  end

  # ---------------------------------------------------------------------
  # 2. Ajout via modal
  # ---------------------------------------------------------------------

  test "ajout via modale : frappe complète avec projet/contexte/tags, Enter, Esc" do
    io = recording_io(self())
    s = state([t("existante", 1), t("autre", 3)], io: io)

    s = key(s, "a")
    assert s.mode == :input and s.modal.action == :add
    assert s.modal.widget_mod == TextInput

    s = type(s, "(B) appeler client +boulot @téléphone due:2026-09-22 t:2026-09-21")

    assert TextInput.get_value(s.modal.widget) ==
             "(B) appeler client +boulot @téléphone due:2026-09-22 t:2026-09-21"

    {:msg, {:modal_event, enter}} = Tui.event_to_msg(Event.key(:enter), s)
    {s, []} = Tui.update({:modal_event, enter}, s)

    assert s.mode == :normal and s.modal == nil
    assert s.status == "4: added"

    # Append (pas write) de la seule nouvelle tâche, numérotée max+1
    assert_received {:append, "t", [new]}
    refute_received {:write, _, _}
    assert new.line == 4

    assert new.raw ==
             "(B) 2026-09-21 appeler client +boulot @téléphone due:2026-09-22 t:2026-09-21"

    assert new.priority == ?B and new.projects == ["+boulot"] and new.contexts == ["@téléphone"]
    assert new.tags == %{"due" => "2026-09-22", "t" => "2026-09-21"}

    # s.tasks mise à jour, la nouvelle est visible (t: = today) et triée en tête
    assert Enum.map(s.tasks, & &1.line) == [1, 3, 4]
    assert hd(State.rows(s)) == {:task, new}

    # Esc annule sans écrire
    {s, []} = Tui.update({:open_modal, :add}, s)
    s = type(s, "brouillon")
    {:msg, {:modal_event, esc}} = Tui.event_to_msg(Event.key(:escape), s)
    {s, []} = Tui.update({:modal_event, esc}, s)
    assert s.mode == :normal and length(s.tasks) == 3
    refute_received {:append, _, _}

    # Texte vide / espaces : fermeture sans mutation
    {s, []} = Tui.update({:open_modal, :add}, s)
    s = type(s, "   ")
    {s, []} = Tui.update(:modal_submit, s)
    assert s.mode == :normal and length(s.tasks) == 3
    refute_received {:append, _, _}

    # Le nouvel ajout hérite du max des lignes existantes même après suppression
    s = %{s | tasks: [t("a", 1), t("z", 9)]}
    {s, []} = Tui.update({:open_modal, :add}, s)
    s = type(s, "dix")
    {_s, []} = Tui.update(:modal_submit, s)
    assert_received {:append, "t", [%{line: 10, description: "dix"}]}
  end

  test "édition via modales edit / A (append) / P (prepend) sur la tâche sélectionnée" do
    io = recording_io(self())
    s = state([t("(A) 2026-09-10 rendre rapport +boulot", 1), t("autre", 2)], io: io)

    # A : append texte — tags ajoutés, priorité et date conservées
    s = key(s, "A")
    assert s.modal.action == :append and s.modal.line == 1
    s = type(s, "@bureau due:2026-09-30")
    {s, []} = Tui.update(:modal_submit, s)
    assert s.status == "1: appended"
    assert_received {:write, "t", [t1, _]}
    assert t1.raw == "(A) 2026-09-10 rendre rapport +boulot @bureau due:2026-09-30"
    assert hd(s.tasks).tags == %{"due" => "2026-09-30"}

    # P : prepend texte
    s = key(s, "P")
    s = type(s, "URGENT")
    {s, []} = Tui.update(:modal_submit, s)
    assert s.status == "1: prepended"

    assert hd(s.tasks).raw ==
             "(A) 2026-09-10 URGENT rendre rapport +boulot @bureau due:2026-09-30"

    # e : edit — pré-rempli avec le raw ; on remplace tout par une ligne reparsée
    s = key(s, "e")
    assert s.modal.action == :edit
    assert TextInput.get_value(s.modal.widget) == hd(s.tasks).raw
    # Le curseur du TextInput est en début de champ : End puis backspace ×n
    {s, []} = Tui.update({:modal_event, Event.key(:end)}, s)

    s =
      Enum.reduce(1..String.length(hd(s.tasks).raw), s, fn _, acc ->
        {acc2, []} = Tui.update({:modal_event, Event.key(:backspace)}, acc)
        acc2
      end)

    assert TextInput.get_value(s.modal.widget) == ""
    s = type(s, "(C) rapport rendu +boulot")
    {s, []} = Tui.update(:modal_submit, s)
    assert s.status == "1: edited"
    assert hd(s.tasks).raw == "(C) rapport rendu +boulot"
    assert hd(s.tasks).priority == ?C and hd(s.tasks).creation_date == nil

    # Sur une liste vide, e/A/P/d/p n'ouvrent rien
    empty = state([])

    for a <- [:edit, :append, :prepend, :del, :pri] do
      assert {^empty, []} = Tui.update({:open_modal, a}, empty)
    end
  end

  # ---------------------------------------------------------------------
  # 3. Complétion + récurrence
  # ---------------------------------------------------------------------

  test "x sur une tâche recur:+1w crée l'occurrence suivante dans le même write" do
    io = recording_io(self())
    # t: doit être atteint (<= today) sinon la tâche est masquée de la liste
    s =
      state([t("autre", 1), t("(B) renouveler t:2026-09-21 due:2026-09-25 recur:+1w", 2)], io: io)

    # Tri : la (B) passe avant la tâche sans priorité
    assert selected(s).line == 2
    s = key(s, "x")

    assert s.status == "2: done"
    assert_received {:write, "t", [_, done, recur]}
    assert done.line == 2 and done.done and done.completion_date == ~D[2026-09-21]
    assert done.priority == nil
    # Nouvelle occurrence : ligne max+1, priorité conservée, t:/due: décalés
    assert recur.line == 3 and recur.done == false and recur.priority == ?B
    assert recur.tags == %{"t" => "2026-09-28", "due" => "2026-09-28", "recur" => "+1w"}
    assert recur.creation_date == ~D[2026-09-21]

    assert Enum.map(s.tasks, & &1.line) == [1, 2, 3]
    # La nouvelle occurrence (t: futur) est masquée : la liste montre 1 et 2 (x)
    rows = Enum.map(State.rows(s), fn {:task, t} -> t.line end)
    assert Enum.sort(rows) == [1, 2]

    # Espace = x aussi : re-toggle réouvre la tâche faite (on la re-sélectionne :
    # la perte de priorité l'a déplacée dans le tri)
    s = %{s | list_idx: Enum.find_index(rows, &(&1 == 2))}
    assert selected(s).line == 2
    s = key(s, " ")
    assert s.status == "2: reopened"
    assert_received {:write, "t", ts}
    refute Enum.at(ts, 1).done
    # La récurrence déjà générée reste (pas d'annulation)
    assert length(ts) == 3

    # recur strict : offset préservé, décalé depuis due:
    s = state([t("strict t:2026-09-21 due:2026-09-25 recur:1w", 1)], io: io)
    {_s, []} = Tui.update(:toggle_done, s)
    assert_received {:write, "t", [_, recur]}
    assert recur.tags["t"] == "2026-09-28" and recur.tags["due"] == "2026-10-02"
  end

  test "x sur recur:bad : toast d'erreur, aucun write, état intact" do
    io = recording_io(self())
    s = state([t("ok", 1), t("cassé recur:bad", 2)], io: io, list_idx: 1)

    s2 = key(s, "x")
    assert s2.status =~ "error" and s2.status =~ "invalid recur" and s2.status =~ "\"bad\""
    assert s2.tasks == s.tasks
    refute Enum.at(s2.tasks, 1).done
    refute_received {:write, _, _}

    # La tâche voisine sans recur se complète normalement ensuite
    s3 = key(s2, "k") |> key("x")
    assert s3.status == "1: done"
    assert_received {:write, "t", [%{line: 1, done: true}, %{line: 2, done: false}]}
  end

  # ---------------------------------------------------------------------
  # 4. Cycle vue :done
  # ---------------------------------------------------------------------

  test "vue :done : x réouvre (append todo, rewrite done, reload des deux)" do
    test_pid = self()
    d1 = t("x 2026-09-19 2026-09-10 ancienne +p", 1)
    d2 = t("x 2026-09-20 2026-09-10 récente +p", 2)
    reopened_in_todo = t("2026-09-10 récente +p", 4)

    io =
      recording_io(self(), %{
        read: fn
          "t" -> send(test_pid, :read_todo) && {:ok, [t("ouverte", 1), reopened_in_todo]}
          "d" -> send(test_pid, :read_done) && {:ok, [d1]}
        end
      })

    s = state([t("ouverte", 1)], io: io, view: :done, done_tasks: [d1, d2])
    # Tri desc par ligne : list_idx 0 = d2 (la plus récente)
    assert selected(s).line == 2

    s = key(s, "x")
    assert s.status == "2: reopened"

    # Ordre : append todo.txt AVANT rewrite done.txt ; todo.txt jamais réécrit
    assert_received {:append, "t", [reopened]}
    refute reopened.done and reopened.completion_date == nil
    assert reopened.description == "récente +p" and reopened.creation_date == ~D[2026-09-10]
    assert_received {:write, "d", [^d1]}
    refute_received {:write, "t", _}

    # Reload : les deux miroirs viennent des lectures factices
    assert_received :read_todo
    assert_received :read_done
    assert s.done_tasks == [d1]
    assert Enum.map(s.tasks, & &1.line) == [1, 4]
    assert s.view == :done and selected(s) == d1

    # Ré-ouvrir la dernière puis toggle sur vue vide = no-op
    io2 = recording_io(self(), %{read: fn _ -> {:ok, []} end})
    s = %{s | io: io2}
    s = key(s, "x")
    assert s.done_tasks == [] and selected(s) == nil
    assert_received {:append, "t", [_]}
    assert {^s, []} = Tui.update(:toggle_done, s)
  end

  test "vue :done : m renvoie la tâche vers todo.txt ; en vue :todo m l'envoie vers done.txt" do
    test_pid = self()
    d1 = t("x 2026-09-19 d1", 5)
    d2 = t("x 2026-09-20 d2", 6)

    # Miroir de fichiers mutable via Agent pour un aller-retour réaliste.
    {:ok, files} = Agent.start_link(fn -> %{"t" => [t("a", 1)], "d" => [d1, d2]} end)

    io = %{
      read: fn p -> {:ok, Agent.get(files, & &1[p])} end,
      write: fn p, ts ->
        send(test_pid, {:write, p, ts})
        Agent.update(files, &Map.put(&1, p, ts))
      end,
      append: fn p, ts ->
        send(test_pid, {:append, p, ts})
        Agent.update(files, fn f -> Map.put(f, p, f[p] ++ ts) end)
      end,
      stat: fn _ -> {:error, :enoent} end
    }

    s = state([t("a", 1)], io: io, view: :done, done_tasks: [d1, d2])
    assert selected(s).line == 6

    s = key(s, "m")
    assert s.status == "6: moved to todo"
    assert_received {:append, "t", [^d2]}
    assert_received {:write, "d", [^d1]}
    # Reload : s.tasks a récupéré d2 (toujours `x`, m ne réouvre pas)
    assert Enum.map(s.tasks, & &1.line) == [1, 6]
    assert Enum.at(s.tasks, 1).done
    assert s.done_tasks == [d1]

    # Retour en vue :todo, sélectionner d2 (ligne 6, tri prio puis ligne) et m
    s = %{s | view: :todo, list_idx: 1}
    assert selected(s).line == 6
    s = key(s, "m")
    assert s.status == "6: moved to done"
    assert_received {:append, "d", [^d2]}
    assert_received {:write, "t", [%{line: 1}]}
    assert Enum.map(s.tasks, & &1.line) == [1]
    assert Enum.map(s.done_tasks, & &1.line) == [5, 6]
    # Clamp : la sélection revient sur la seule ligne restante
    assert s.list_idx == 0

    # m en vue :agenda est un no-op
    ag = %{s | view: :agenda}
    assert {^ag, []} = Tui.update(:move, ag)
  end

  # ---------------------------------------------------------------------
  # 5. Priorité via PickList
  # ---------------------------------------------------------------------

  test "p ouvre la PickList ; {:select, X} pose/retire la priorité ; done refusé" do
    io = recording_io(self())
    s = state([t("2026-09-10 sans prio +p", 1), t("(A) 2026-09-10 haute", 2)], io: io)

    s = key(s, "p")
    assert s.mode == :input and s.modal.action == :pri
    assert s.modal.widget_mod == TermUI.Widget.PickList
    # La sélection courante est la tâche (A) (tri prio) → line 2
    assert s.modal.line == 2

    {s, []} = Tui.update({:select, "C"}, s)
    assert s.mode == :normal and s.modal == nil
    assert s.status == "2: priority"
    assert_received {:write, "t", ts}
    assert Enum.find(ts, &(&1.line == 2)).raw == "(C) 2026-09-10 haute"

    # La liste est retriée : la (C) passe après... non — seule tâche à prio, reste 1re
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [2, 1]

    # Sélectionner la tâche sans prio et lui donner A → elle passe en tête
    s = key(s, "j")
    assert selected(s).line == 1
    {s, []} = Tui.update({:open_modal, :pri}, s)
    {s, []} = Tui.update({:select, "A"}, s)
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [1, 2]
    assert Enum.find(s.tasks, &(&1.line == 1)).raw == "(A) 2026-09-10 sans prio +p"

    # "(aucune)" retire la priorité
    {s, []} = Tui.update({:open_modal, :pri}, %{s | list_idx: 0})
    {s, []} = Tui.update({:select, "(aucune)"}, s)
    assert Enum.find(s.tasks, &(&1.line == 1)).priority == nil
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [2, 1]

    # :cancel de la PickList ferme sans mutation
    {s, []} = Tui.update({:open_modal, :pri}, s)
    {s, []} = Tui.update(:cancel, s)
    assert s.mode == :normal and s.modal == nil

    # Priorité sur une tâche faite : erreur, pas de write
    # (on vide d'abord les writes des étapes précédentes)
    assert_received {:write, _, _}
    assert_received {:write, _, _}
    refute_received {:write, _, _}
    s = state([t("x 2026-09-20 finie", 1)], io: io)
    {s, []} = Tui.update({:open_modal, :pri}, s)
    {s, []} = Tui.update({:select, "B"}, s)
    assert s.status =~ "error" and s.status =~ "already done"
    refute_received {:write, _, _}
  end

  # ---------------------------------------------------------------------
  # 6. Suppression avec confirmation + clamp
  # ---------------------------------------------------------------------

  test "d + confirmation supprime ; :no annule ; clamp sur la dernière ligne" do
    io = recording_io(self())
    s = state([t("a", 1), t("b", 2), t("c", 3)], io: io)

    # Aller en bas de liste
    s = s |> key("j") |> key("j")
    assert s.list_idx == 2 and selected(s).line == 3

    s = key(s, "d")
    assert s.mode == :input and s.modal.action == :del and s.modal.line == 3
    assert s.modal.widget_mod == TermUI.Widgets.AlertDialog

    # :no ferme sans toucher
    {s, []} = Tui.update({:dialog_result, :no}, s)
    assert s.mode == :normal and length(s.tasks) == 3
    refute_received {:write, _, _}

    # :yes supprime la dernière ligne → list_idx clampé à 1
    {s, []} = Tui.update({:open_modal, :del}, s)
    {s, []} = Tui.update({:dialog_result, :yes}, s)
    assert s.status == "3: deleted"
    assert Enum.map(s.tasks, & &1.line) == [1, 2]
    assert s.list_idx == 1 and selected(s).line == 2
    assert_received {:write, "t", [%{line: 1}, %{line: 2}]}

    # Supprimer encore la dernière
    {s, []} = Tui.update({:open_modal, :del}, s)
    {s, []} = Tui.update({:dialog_result, :yes}, s)
    assert s.list_idx == 0 and Enum.map(s.tasks, & &1.line) == [1]

    # Puis la seule restante : liste vide, idx 0, d ne s'ouvre plus
    {s, []} = Tui.update({:open_modal, :del}, s)
    {s, []} = Tui.update({:dialog_result, :confirm}, s)
    assert s.tasks == [] and s.list_idx == 0
    assert {^s, []} = Tui.update({:open_modal, :del}, s)

    # Suppression sous filtre : le write garde les tâches hors filtre
    s = state([t("a +x", 1), t("b", 2), t("c +x", 3)], io: io, filter_terms: ["+x"], list_idx: 1)
    assert selected(s).line == 3
    {s, []} = Tui.update({:open_modal, :del}, s)
    {s, []} = Tui.update({:dialog_result, :yes}, s)
    assert_received {:write, "t", [%{line: 1}, %{line: 2}]}
    assert s.list_idx == 0 and selected(s).line == 1
  end

  # ---------------------------------------------------------------------
  # 7. Archivage
  # ---------------------------------------------------------------------

  test "R + confirmation archive : append done, rewrite todo, reload done_tasks" do
    test_pid = self()
    open = t("(A) ouverte", 1)
    d1 = t("x 2026-09-20 finie1", 2)
    d2 = t("x 2026-09-21 finie2 recur:+1w due:2026-09-28", 3)
    old = t("x 2026-09-01 très ancienne", 1)

    {:ok, files} = Agent.start_link(fn -> %{"t" => [open, d1, d2], "d" => [old]} end)

    io = %{
      read: fn p -> send(test_pid, {:read, p}) && {:ok, Agent.get(files, & &1[p])} end,
      write: fn p, ts ->
        send(test_pid, {:write, p, ts})
        Agent.update(files, &Map.put(&1, p, ts))
      end,
      append: fn p, ts ->
        send(test_pid, {:append, p, ts})
        Agent.update(files, fn f -> Map.put(f, p, f[p] ++ ts) end)
      end,
      stat: fn _ -> {:error, :enoent} end
    }

    s = state([open, d1, d2], io: io, list_idx: 2)
    assert State.counts(s) == %{open: 1, done: 2}

    s = key(s, "R")
    assert s.mode == :input and s.modal.action == :archive
    # La modale d'archive n'est pas liée à une tâche
    refute Map.has_key?(s.modal, :line)

    {s, []} = Tui.update({:dialog_result, :yes}, s)
    assert s.status == "archived 2"
    assert_received {:append, "d", [^d1, ^d2]}
    assert_received {:write, "t", [^open]}
    assert_received {:read, "t"}
    assert_received {:read, "d"}

    assert s.tasks == [open]
    # done_tasks vient du reload : ancien contenu + archivées (numéros de done.txt)
    assert Enum.map(s.done_tasks, & &1.description) == [
             "très ancienne",
             "finie1",
             "finie2 recur:+1w due:2026-09-28"
           ]

    # Clamp de la sélection sur la seule ligne restante
    assert s.list_idx == 0 and selected(s) == open

    # Rien à archiver : pas d'append, todo réécrit à l'identique, "archived 0"
    {s, []} = Tui.update({:open_modal, :archive}, s)
    {s, []} = Tui.update({:dialog_result, :ok}, s)
    assert s.status == "archived 0"
    refute_received {:append, "d", _}
    assert_received {:write, "t", [^open]}

    # :no laisse tout en place
    s = state([open, d1], io: io)
    {s, []} = Tui.update({:open_modal, :archive}, s)
    {s, []} = Tui.update({:dialog_result, :no}, s)
    assert s.tasks == [open, d1] and s.mode == :normal
    refute_received {:write, "t", _}
  end

  # ---------------------------------------------------------------------
  # 8. Watch externe
  # ---------------------------------------------------------------------

  test "tick : mtime changée → reload avec toast ; inchangée → no-op strict" do
    test_pid = self()
    m0 = {{2026, 9, 21}, {10, 0, 0}}
    m1 = {{2026, 9, 21}, {10, 0, 5}}
    mtimes = Agent.start_link(fn -> %{"t" => m0, "d" => m0} end) |> elem(1)
    files = Agent.start_link(fn -> %{"t" => [t("a", 1), t("b", 2)], "d" => []} end) |> elem(1)

    io = %{
      read: fn p -> send(test_pid, {:read, p}) && {:ok, Agent.get(files, & &1[p])} end,
      write: fn _, _ -> :ok end,
      append: fn _, _ -> :ok end,
      stat: fn p -> {:ok, %{mtime: Agent.get(mtimes, & &1[p])}} end
    }

    s = state([t("a", 1), t("b", 2)], io: io, list_idx: 1) |> State.refresh_mtimes()
    assert s.mtimes == %{todo: m0, done: m0}

    # Aucun changement : struct strictement identique, aucune lecture
    assert {^s, []} = Tui.update(:tick, s)
    refute_received {:read, _}

    # Édition externe : b supprimée, c ajoutée dans done.txt, mtimes avancées
    Agent.update(files, fn _ -> %{"t" => [t("a", 1)], "d" => [t("x 2026-09-21 c", 1)]} end)
    Agent.update(mtimes, fn _ -> %{"t" => m1, "d" => m0} end)

    {s2, []} = Tui.update(:tick, s)
    assert_received {:read, "t"}
    assert_received {:read, "d"}
    assert s2.status =~ "rechargé"
    assert Enum.map(s2.tasks, & &1.line) == [1]
    assert length(s2.done_tasks) == 1
    # mtimes rafraîchies et sélection clampée
    assert s2.mtimes == %{todo: m1, done: m0}
    assert s2.list_idx == 0

    # Le tick suivant est à nouveau un no-op
    assert {^s2, []} = Tui.update(:tick, s2)
    refute_received {:read, _}

    # Seul done.txt change → reload aussi
    Agent.update(mtimes, fn _ -> %{"t" => m1, "d" => m1} end)
    {s3, []} = Tui.update(:tick, s2)
    assert s3.mtimes.done == m1
    assert_received {:read, "d"}

    # Fichier disparu (stat enoent) : mtime nil ≠ ancienne → reload sans crash
    io_gone = %{io | stat: fn _ -> {:error, :enoent} end, read: fn _ -> {:ok, []} end}
    {s4, []} = Tui.update(:tick, %{s3 | io: io_gone})
    assert s4.mtimes == %{todo: nil, done: nil} and s4.tasks == []

    # r force le reload même sans changement de mtime
    {s5, []} = Tui.update(:reload, s3)
    assert_received {:read, "t"}
    assert s5.mtimes == s3.mtimes
  end

  # ---------------------------------------------------------------------
  # 9. Robustesse io
  # ---------------------------------------------------------------------

  test "erreurs io : write/append en échec atterrissent dans status, état non muté" do
    # write KO sur toggle_done : la tâche reste ouverte
    io = %{fake_io() | write: fn _, _ -> {:error, "disk full"} end}
    s = state([t("a", 1)], io: io)
    {s2, []} = Tui.update(:toggle_done, s)
    assert s2.status == "error: disk full"
    refute hd(s2.tasks).done
    assert s2.mode == :normal

    # write KO sur delete / priorité / edit : tasks intactes
    {s3, []} = Tui.update({:open_modal, :del}, s2)
    {s3, []} = Tui.update({:dialog_result, :yes}, s3)
    assert s3.status == "error: disk full" and length(s3.tasks) == 1

    {s4, []} = Tui.update({:open_modal, :pri}, s3)
    {s4, []} = Tui.update({:select, "A"}, s4)
    assert s4.status == "error: disk full" and hd(s4.tasks).priority == nil

    {s5, []} = Tui.update({:open_modal, :append}, s4)
    s5 = type(s5, "+p")
    {s5, []} = Tui.update(:modal_submit, s5)
    assert s5.status == "error: disk full" and hd(s5.tasks).raw == "a"

    # append KO sur add : s.tasks inchangée
    io_add = %{fake_io() | append: fn _, _ -> {:error, "read-only fs"} end}
    s = state([t("a", 1)], io: io_add)
    {s, []} = Tui.update({:open_modal, :add}, s)
    s = type(s, "nouvelle")
    {s, []} = Tui.update(:modal_submit, s)
    assert s.status == "error: read-only fs" and length(s.tasks) == 1

    # La mutation suivante, si l'io se rétablit, repart proprement
    s = %{s | io: fake_io()}
    {s, []} = Tui.update(:toggle_done, s)
    assert s.status == "1: done"
  end

  test "move : échec de l'append saute la réécriture source ET le reload" do
    test_pid = self()

    io = %{
      fake_io()
      | append: fn _, _ -> {:error, "disk full"} end,
        write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end,
        read: fn _ -> send(test_pid, :read) && {:ok, []} end
    }

    s = state([t("a", 1)], io: io)
    {s2, []} = Tui.update(:move, s)
    assert s2.status == "error: disk full"
    assert s2.tasks == s.tasks
    refute_received {:write, _, _}
    refute_received :read

    # Même garantie en vue :done (reopen = move inversé) et pour archive
    d = t("x 2026-09-20 fini", 3)
    s = state([t("a", 1)], io: io, view: :done, done_tasks: [d])
    {s2, []} = Tui.update(:toggle_done, s)
    assert s2.status == "error: disk full" and s2.done_tasks == [d]
    refute_received {:write, _, _}
    refute_received :read

    s = state([t("a", 1), d], io: io)
    {s2, []} = Tui.update({:open_modal, :archive}, s)
    {s3, []} = Tui.update({:dialog_result, :yes}, s2)
    assert s3.status == "error: disk full" and length(s3.tasks) == 2
    refute_received {:write, _, _}
    refute_received :read
  end

  test "reload en échec (fichier illisible) : status erreur, listes conservées" do
    io = %{
      fake_io()
      | read: fn
          "t" -> {:error, "cannot read t: is a directory"}
          _ -> {:ok, []}
        end
    }

    s = state([t("a", 1)], io: io)
    {s2, []} = Tui.update(:reload, s)
    assert s2.status == "error: cannot read t: is a directory"
    assert s2.tasks == s.tasks

    # Après une réouverture en vue :done dont le reload échoue : les writes
    # ont eu lieu, le miroir done_tasks est mis à jour, le status signale l'erreur
    test_pid = self()
    io2 = %{io | append: fn p, _ -> send(test_pid, {:append, p}) && :ok end}
    s = state([], io: io2, view: :done, done_tasks: [t("x 2026-09-20 fini", 1)])
    {s2, []} = Tui.update(:toggle_done, s)
    assert_received {:append, "t"}
    assert s2.done_tasks == []
    assert s2.status =~ "error: cannot read"
  end
end
