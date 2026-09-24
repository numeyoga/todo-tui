defmodule TodoTxt.CLIScenariosTest do
  @moduledoc """
  Scénarios de bout en bout via `TodoTxt.CLI.run/2` : chaque test enchaîne
  plusieurs commandes sur les mêmes fichiers tmp (persistants pendant le
  test) et vérifie l'état résultant via `TodoTxt.Store.read/1` et/ou les
  messages retournés. `today` est figé pour le déterminisme des dates.
  """
  use ExUnit.Case

  alias TodoTxt.{CLI, Store}

  @today ~D[2026-09-21]

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ttcli#{System.system_time(:nanosecond)}#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    env = %{
      paths: %{
        todo: Path.join(dir, "todo.txt"),
        done: Path.join(dir, "done.txt"),
        report: Path.join(dir, "report.txt")
      },
      today: @today,
      config: %{}
    }

    %{env: env, dir: dir}
  end

  defp raws(path) do
    {:ok, ts} = Store.read(path)
    Enum.map(ts, & &1.raw)
  end

  defp by_line(path, n) do
    {:ok, ts} = Store.read(path)
    Enum.find(ts, &(&1.line == n))
  end

  defp lines(out), do: String.split(out, "\n")

  # ---------------------------------------------------------------------
  # 1. Semaine GTD
  # ---------------------------------------------------------------------

  test "semaine GTD : add x3, pri, depri, do, archive", %{env: e} do
    assert {:ok, out} = CLI.run(["add", "(A) préparer réunion +boulot @bureau due:2026-09-22"], e)
    assert out == "1: (A) 2026-09-21 préparer réunion +boulot @bureau due:2026-09-22"

    assert {:ok, out} = CLI.run(["add", "acheter lait +courses @magasin"], e)
    assert out == "2: 2026-09-21 acheter lait +courses @magasin"

    assert {:ok, out} = CLI.run(["add", "appeler client +boulot @téléphone due:2026-09-21"], e)
    assert out == "3: 2026-09-21 appeler client +boulot @téléphone due:2026-09-21"

    {:ok, [t1, t2, t3]} = Store.read(e.paths.todo)
    assert {t1.line, t2.line, t3.line} == {1, 2, 3}
    assert t1.priority == ?A and t2.priority == nil and t3.priority == nil
    assert t1.projects == ["+boulot"] and t1.contexts == ["@bureau"]
    assert t1.tags == %{"due" => "2026-09-22"}
    assert t3.contexts == ["@téléphone"]
    assert Enum.all?([t1, t2, t3], &(&1.creation_date == @today))

    # ls : tri par priorité puis ligne
    assert {:ok, out} = CLI.run(["--plain", "ls"], e)

    assert lines(out) == [
             "1: (A) 2026-09-21 préparer réunion +boulot @bureau due:2026-09-22",
             "2: 2026-09-21 acheter lait +courses @magasin",
             "3: 2026-09-21 appeler client +boulot @téléphone due:2026-09-21"
           ]

    # pri 2 B : la priorité s'insère AVANT la date de création
    assert {:ok, out} = CLI.run(["pri", "2", "B"], e)
    assert out == "2: (B) 2026-09-21 acheter lait +courses @magasin"
    assert by_line(e.paths.todo, 2).priority == ?B
    assert by_line(e.paths.todo, 2).creation_date == @today

    # depri 1 : (A) disparaît, la date de création reste
    assert {:ok, "1: deprioritized"} = CLI.run(["depri", "1"], e)
    t1 = by_line(e.paths.todo, 1)
    assert t1.priority == nil
    assert t1.raw == "2026-09-21 préparer réunion +boulot @bureau due:2026-09-22"

    # ls reflète le nouveau tri : (B) en tête, numéros de ligne stables
    assert {:ok, out} = CLI.run(["--plain", "ls"], e)
    assert Enum.map(lines(out), &String.slice(&1, 0, 2)) == ["2:", "1:", "3:"]

    # do 3 : x + date de complétion, tags/projets conservés
    assert {:ok, out} = CLI.run(["do", "3"], e)
    assert out == "3: x 2026-09-21 2026-09-21 appeler client +boulot @téléphone due:2026-09-21"
    t3 = by_line(e.paths.todo, 3)
    assert t3.done and t3.completion_date == @today and t3.creation_date == @today
    assert t3.projects == ["+boulot"] and t3.tags["due"] == "2026-09-21"

    # La tâche faite reste visible dans ls jusqu'à l'archivage
    assert {:ok, out} = CLI.run(["--plain", "ls"], e)
    assert out =~ "3: x 2026-09-21"
    # ... mais plus dans due (tâches faites exclues)
    assert {:ok, out} = CLI.run(["--plain", "due"], e)
    refute out =~ "appeler client"
    assert out =~ "préparer réunion"

    # archive : la tâche faite part dans done.txt, todo.txt garde 2 lignes renumérotées
    assert {:ok, "archived 1 tasks"} = CLI.run(["archive"], e)

    assert raws(e.paths.todo) == [
             "2026-09-21 préparer réunion +boulot @bureau due:2026-09-22",
             "(B) 2026-09-21 acheter lait +courses @magasin"
           ]

    assert raws(e.paths.done) == [
             "x 2026-09-21 2026-09-21 appeler client +boulot @téléphone due:2026-09-21"
           ]

    # Limite constatée : todo.txt est réécrit compacté, les numéros de ligne
    # sont donc renumérotés après archive (1,2) — comme todo.sh.
    {:ok, ts} = Store.read(e.paths.todo)
    assert Enum.map(ts, & &1.line) == [1, 2]

    # listall voit les deux fichiers ; le done a le numéro de ligne de done.txt
    assert {:ok, out} = CLI.run(["--plain", "listall"], e)

    assert lines(out) == [
             "2: (B) 2026-09-21 acheter lait +courses @magasin",
             "1: 2026-09-21 préparer réunion +boulot @bureau due:2026-09-22",
             "1: x 2026-09-21 2026-09-21 appeler client +boulot @téléphone due:2026-09-21"
           ]

    # archive à vide : done.txt inchangé
    assert {:ok, "archived 0 tasks"} = CLI.run(["archive"], e)
    assert length(raws(e.paths.done)) == 1
  end

  # ---------------------------------------------------------------------
  # 2. Récurrence multi-itérations
  # ---------------------------------------------------------------------

  test "récurrence non-stricte +1w : deux itérations décalent t: et due: depuis today",
       %{env: e} do
    assert {:ok, "1: " <> _} =
             CLI.run(["add", "renouveler abo t:2026-09-24 due:2026-09-25 recur:+1w"], e)

    # 1re complétion : la nouvelle occurrence est ajoutée en ligne 2
    assert {:ok, out} = CLI.run(["do", "1"], e)

    assert lines(out) == [
             "1: x 2026-09-21 2026-09-21 renouveler abo t:2026-09-24 due:2026-09-25 recur:+1w",
             "2: 2026-09-21 renouveler abo t:2026-09-28 due:2026-09-28 recur:+1w"
           ]

    {:ok, [old, new]} = Store.read(e.paths.todo)
    assert old.done and old.tags["due"] == "2026-09-25"
    refute new.done
    assert new.line == 2 and new.creation_date == @today
    # Mode non-strict : t: et due: sont tous deux recalculés depuis today,
    # l'offset t:↔due: (1 jour) est perdu — comportement documenté.
    assert new.tags == %{"t" => "2026-09-28", "due" => "2026-09-28", "recur" => "+1w"}

    # La nouvelle occurrence a t: dans le futur → masquée de ls
    assert {:ok, out} = CLI.run(["--plain", "ls"], e)
    refute out =~ "2: "
    assert out =~ "1: x "

    # 2e itération sur la ligne 2 → ligne 3 (max+1)
    assert {:ok, out} = CLI.run(["do", "2"], e)
    assert out =~ "3: 2026-09-21 renouveler abo t:2026-09-28 due:2026-09-28 recur:+1w"
    {:ok, ts} = Store.read(e.paths.todo)
    assert Enum.map(ts, &{&1.line, &1.done}) == [{1, true}, {2, true}, {3, false}]

    # Après archive, seule l'occurrence ouverte reste, renumérotée en 1
    assert {:ok, "archived 2 tasks"} = CLI.run(["archive"], e)
    {:ok, [only]} = Store.read(e.paths.todo)
    assert only.line == 1 and only.tags["recur"] == "+1w"
    assert length(raws(e.paths.done)) == 2
  end

  test "récurrence stricte 1w : décalage depuis due:, offset t:↔due: préservé", %{env: e} do
    {:ok, _} = CLI.run(["add", "(B) renouveler abo t:2026-09-24 due:2026-09-25 recur:1w"], e)

    assert {:ok, out} = CLI.run(["do", "1"], e)
    # La priorité tombe sur la tâche faite mais est conservée sur la récurrence
    assert lines(out) == [
             "1: x 2026-09-21 2026-09-21 renouveler abo t:2026-09-24 due:2026-09-25 recur:1w",
             "2: (B) 2026-09-21 renouveler abo t:2026-10-01 due:2026-10-02 recur:1w"
           ]

    new = by_line(e.paths.todo, 2)
    assert new.priority == ?B
    assert new.tags["t"] == "2026-10-01" and new.tags["due"] == "2026-10-02"

    # 2e itération : toujours +7j depuis l'ancien due:, indépendant de today
    assert {:ok, out} = CLI.run(["do", "2"], e)
    assert out =~ "3: (B) 2026-09-21 renouveler abo t:2026-10-08 due:2026-10-09 recur:1w"
    assert by_line(e.paths.todo, 3).tags["due"] == "2026-10-09"
  end

  test "récurrence : unités d/m/y et recur: sans due: initial", %{env: e} do
    {:ok, _} = CLI.run(["add", "quotidien recur:+1d"], e)
    {:ok, _} = CLI.run(["add", "loyer due:2026-09-30 recur:1m"], e)
    {:ok, _} = CLI.run(["add", "anniversaire due:2026-09-21 recur:1y"], e)

    # Sans due: : la récurrence ajoute due: = today + 1d
    assert {:ok, out} = CLI.run(["do", "1"], e)
    assert out =~ "4: 2026-09-21 quotidien recur:+1d due:2026-09-22"

    assert {:ok, out} = CLI.run(["do", "2"], e)
    assert out =~ "5: 2026-09-21 loyer due:2026-10-30 recur:1m"

    assert {:ok, out} = CLI.run(["do", "3"], e)
    assert out =~ "6: 2026-09-21 anniversaire due:2027-09-21 recur:1y"

    {:ok, ts} = Store.read(e.paths.todo)
    assert Enum.count(ts, & &1.done) == 3 and Enum.count(ts, &(not &1.done)) == 3
  end

  test "récurrence malformée : erreur, fichier intact, puis correction via replace",
       %{env: e} do
    {:ok, _} = CLI.run(["add", "sport recur:hebdo"], e)
    before = File.read!(e.paths.todo)
    assert {:error, m} = CLI.run(["do", "1"], e)
    assert m =~ "hebdo" and m =~ "1"
    assert File.read!(e.paths.todo) == before

    {:ok, _} = CLI.run(["replace", "1", "2026-09-21 sport recur:+1w"], e)
    assert {:ok, out} = CLI.run(["do", "1"], e)
    assert out =~ "2: 2026-09-21 sport recur:+1w due:2026-09-28"
  end

  # ---------------------------------------------------------------------
  # 3. Vues et rapports multi-projets
  # ---------------------------------------------------------------------

  defp populate_views(e) do
    File.write!(
      e.paths.todo,
      Enum.join(
        [
          "(A) 2026-09-10 rendre rapport +boulot @bureau due:2026-09-19",
          "(C) 2026-09-10 relire specs +boulot @bureau due:2026-09-21",
          "2026-09-10 acheter pain +courses @magasin due:2026-09-24",
          "(A) 2026-09-10 déclarer impôts +perso @maison due:2026-10-15",
          "(B) 2026-09-10 appeler mamie +perso @téléphone",
          "x 2026-09-20 2026-09-10 tâche finie +boulot @bureau due:2026-09-19"
        ],
        "\n"
      ) <> "\n"
    )

    File.write!(
      e.paths.done,
      "x 2026-09-15 2026-09-01 ancien projet +archive @bureau\n"
    )
  end

  test "vues : ls filtré, listproj/listcon/listpri, due, agenda (texte)", %{env: e} do
    populate_views(e)

    # ls +boulot : filtre projet exact, tri prio puis ligne, done inclus
    assert {:ok, out} = CLI.run(["--plain", "ls", "+boulot"], e)

    assert lines(out) == [
             "1: (A) 2026-09-10 rendre rapport +boulot @bureau due:2026-09-19",
             "2: (C) 2026-09-10 relire specs +boulot @bureau due:2026-09-21",
             "6: x 2026-09-20 2026-09-10 tâche finie +boulot @bureau due:2026-09-19"
           ]

    # AND de plusieurs termes : projet + contexte + texte libre insensible à la casse
    assert {:ok, out} = CLI.run(["--plain", "ls", "+perso", "@maison"], e)
    assert lines(out) == ["4: (A) 2026-09-10 déclarer impôts +perso @maison due:2026-10-15"]
    assert {:ok, out} = CLI.run(["--plain", "ls", "APPELER"], e)
    assert lines(out) == ["5: (B) 2026-09-10 appeler mamie +perso @téléphone"]
    assert {:ok, ""} = CLI.run(["--plain", "ls", "+inexistant"], e)

    # listproj / listcon agrègent todo.txt ET done.txt, triés et dédupliqués
    assert {:ok, out} = CLI.run(["--plain", "listproj"], e)
    assert lines(out) == ["+archive", "+boulot", "+courses", "+perso"]
    assert {:ok, out} = CLI.run(["--plain", "listcon"], e)
    assert lines(out) == ["@bureau", "@magasin", "@maison", "@téléphone"]

    # listpri A : uniquement todo.txt, tri par ligne
    assert {:ok, out} = CLI.run(["--plain", "listpri", "A"], e)
    assert Enum.map(lines(out), &String.slice(&1, 0, 2)) == ["1:", "4:"]
    assert {:ok, ""} = CLI.run(["--plain", "listpri", "Z"], e)
    assert {:usage, _} = CLI.run(["listpri", "a"], e)

    # due : 4 buckets, tâches faites et sans due: exclues
    assert {:ok, out} = CLI.run(["--plain", "due"], e)
    [overdue, today, week, later] = String.split(out, "\n\n")

    assert lines(overdue) == [
             "OVERDUE:",
             "1: (A) 2026-09-10 rendre rapport +boulot @bureau due:2026-09-19"
           ]

    assert lines(today) == [
             "TODAY:",
             "2: (C) 2026-09-10 relire specs +boulot @bureau due:2026-09-21"
           ]

    assert lines(week) == [
             "THIS WEEK:",
             "3: 2026-09-10 acheter pain +courses @magasin due:2026-09-24"
           ]

    assert lines(later) == [
             "LATER:",
             "4: (A) 2026-09-10 déclarer impôts +perso @maison due:2026-10-15"
           ]

    refute out =~ "appeler mamie" or out =~ "tâche finie"

    # agenda : 14 jours, groupé par date, overdue et LATER exclus
    assert {:ok, out} = CLI.run(["--plain", "agenda"], e)

    assert lines(out) == [
             "2026-09-21:",
             "2: (C) 2026-09-10 relire specs +boulot @bureau due:2026-09-21",
             "",
             "2026-09-24:",
             "3: 2026-09-10 acheter pain +courses @magasin due:2026-09-24"
           ]
  end

  test "vues : équivalents --json décodables", %{env: e} do
    populate_views(e)

    assert {:ok, j} = CLI.run(["--json", "ls", "+boulot"], e)
    decoded = Jason.decode!(j)
    assert Enum.map(decoded, & &1["line"]) == [1, 2, 6]

    assert %{
             "line" => 1,
             "done" => false,
             "priority" => "A",
             "creation_date" => "2026-09-10",
             "completion_date" => nil,
             "description" => "rendre rapport +boulot @bureau due:2026-09-19",
             "projects" => ["+boulot"],
             "contexts" => ["@bureau"],
             "tags" => %{"due" => "2026-09-19"}
           } = hd(decoded)

    done = List.last(decoded)
    assert done["done"] == true and done["completion_date"] == "2026-09-20"
    assert done["priority"] == nil

    assert {:ok, j} = CLI.run(["--json", "listproj"], e)
    assert Jason.decode!(j) == ["+archive", "+boulot", "+courses", "+perso"]
    assert {:ok, j} = CLI.run(["--json", "listcon"], e)
    assert Jason.decode!(j) == ["@bureau", "@magasin", "@maison", "@téléphone"]

    # listpri --json : le format JSON n'est pas géré par listpri (sortie texte).
    # Limite constatée : ListMeta.run(["pri", _]) passe par Format.tasks/2.
    assert {:ok, out} = CLI.run(["--json", "listpri", "A"], e)
    assert out =~ "1: (A)"

    assert {:ok, j} = CLI.run(["--json", "due"], e)
    due = Jason.decode!(j)

    assert Enum.map(due, &{&1["line"], &1["bucket"]}) ==
             [{1, "overdue"}, {2, "today"}, {3, "week"}, {4, "later"}]

    assert {:ok, j} = CLI.run(["--json", "agenda"], e)
    assert %{"dates" => dates, "thresholds" => []} = Jason.decode!(j)
    assert Map.keys(dates) |> Enum.sort() == ["2026-09-21", "2026-09-24"]
    assert [%{"line" => 2}] = dates["2026-09-21"]
    assert [%{"line" => 3}] = dates["2026-09-24"]

    assert {:ok, j} = CLI.run(["--json", "listall"], e)
    all = Jason.decode!(j)
    assert length(all) == 7
    assert Enum.count(all, & &1["done"]) == 2
  end

  # ---------------------------------------------------------------------
  # 4. Seuils t:
  # ---------------------------------------------------------------------

  test "seuils t: : masqués de ls, visibles dans agenda THRESHOLDS", %{env: e} do
    {:ok, _} = CLI.run(["add", "visible maintenant"], e)
    {:ok, _} = CLI.run(["add", "seuil aujourd'hui t:2026-09-21"], e)
    {:ok, _} = CLI.run(["add", "seuil passé t:2026-09-01"], e)
    {:ok, _} = CLI.run(["add", "seuil proche t:2026-09-25 due:2026-09-30"], e)
    {:ok, _} = CLI.run(["add", "seuil lointain t:2027-01-01"], e)
    {:ok, _} = CLI.run(["add", "seuil invalide t:demain"], e)

    # ls : t: <= today visible ; t: futur masqué ; t: invalide ignoré (visible)
    assert {:ok, out} = CLI.run(["--plain", "ls"], e)
    assert Enum.map(lines(out), &String.slice(&1, 0, 2)) == ["1:", "2:", "3:", "6:"]
    refute out =~ "seuil proche" or out =~ "seuil lointain"

    # Le filtrage ne contourne pas le masquage
    assert {:ok, ""} = CLI.run(["--plain", "ls", "lointain"], e)

    # agenda : la tâche proche apparaît par sa due: ET dans THRESHOLDS
    assert {:ok, out} = CLI.run(["--plain", "agenda"], e)
    [dates, thresholds] = String.split(out, "\n\n")

    assert lines(dates) == [
             "2026-09-30:",
             "4: 2026-09-21 seuil proche t:2026-09-25 due:2026-09-30"
           ]

    # t: today est dans la fenêtre [today, today+14] → listé aussi
    assert lines(thresholds) == [
             "THRESHOLDS:",
             "2: 2026-09-21 seuil aujourd'hui t:2026-09-21",
             "4: 2026-09-21 seuil proche t:2026-09-25 due:2026-09-30"
           ]

    refute out =~ "lointain" or out =~ "passé"

    assert {:ok, j} = CLI.run(["--json", "agenda"], e)
    assert %{"thresholds" => [%{"line" => 2}, %{"line" => 4}]} = Jason.decode!(j)

    # Une tâche masquée reste adressable par son numéro de ligne
    assert {:ok, out} = CLI.run(["pri", "5", "A"], e)
    assert out == "5: (A) 2026-09-21 seuil lointain t:2027-01-01"
    assert {:ok, out} = CLI.run(["--plain", "ls"], e)
    refute out =~ "lointain"

    # Une tâche faite est toujours visible, même avec t: futur
    {:ok, _} = CLI.run(["do", "5"], e)
    assert {:ok, out} = CLI.run(["--plain", "ls"], e)
    assert out =~ "5: x 2026-09-21 2026-09-21 seuil lointain t:2027-01-01"
  end

  # ---------------------------------------------------------------------
  # 5. Édition incrémentale
  # ---------------------------------------------------------------------

  test "édition incrémentale : add, append, prepend, replace, pri, del TERM", %{env: e} do
    {:ok, _} = CLI.run(["add", "écrire doc"], e)

    assert {:ok, out} = CLI.run(["append", "1", "+projet @bureau due:2026-09-30"], e)
    assert out == "1: 2026-09-21 écrire doc +projet @bureau due:2026-09-30"
    t = by_line(e.paths.todo, 1)
    assert t.projects == ["+projet"] and t.contexts == ["@bureau"]
    assert t.tags == %{"due" => "2026-09-30"}

    assert {:ok, out} = CLI.run(["prepend", "1", "URGENT"], e)
    assert out == "1: 2026-09-21 URGENT écrire doc +projet @bureau due:2026-09-30"
    assert by_line(e.paths.todo, 1).creation_date == @today

    assert {:ok, out} = CLI.run(["pri", "1", "A"], e)
    assert out == "1: (A) 2026-09-21 URGENT écrire doc +projet @bureau due:2026-09-30"

    # append multi-mots : rejoint par des espaces, la priorité reste en tête
    assert {:ok, out} = CLI.run(["append", "1", "t:2026-09-22", "recur:+1w"], e)

    assert out ==
             "1: (A) 2026-09-21 URGENT écrire doc +projet @bureau due:2026-09-30 t:2026-09-22 recur:+1w"

    t = by_line(e.paths.todo, 1)
    assert t.priority == ?A
    assert t.tags == %{"due" => "2026-09-30", "t" => "2026-09-22", "recur" => "+1w"}

    # del N TERM : retire un token précis, le reste est intact
    assert {:ok, out} = CLI.run(["del", "1", "recur:+1w"], e)

    assert out ==
             "1: (A) 2026-09-21 URGENT écrire doc +projet @bureau due:2026-09-30 t:2026-09-22"

    refute Map.has_key?(by_line(e.paths.todo, 1).tags, "recur")

    # replace : la ligne complète est reparsée — la priorité et la date de
    # création ne sont PAS conservées si absentes du nouveau texte
    assert {:ok, out} = CLI.run(["replace", "1", "(B) 2026-09-01 relire doc +projet"], e)
    assert out == "1: (B) 2026-09-01 relire doc +projet"
    t = by_line(e.paths.todo, 1)
    assert t.priority == ?B and t.creation_date == ~D[2026-09-01]
    assert t.contexts == [] and t.tags == %{}

    assert {:ok, out} = CLI.run(["replace", "1", "sans rien"], e)
    assert out == "1: sans rien"
    t = by_line(e.paths.todo, 1)
    assert t.priority == nil and t.creation_date == nil
    assert t.raw == "sans rien"

    # depri sur une tâche sans priorité : no-op idempotent
    assert {:ok, _} = CLI.run(["depri", "1"], e)
    assert by_line(e.paths.todo, 1).raw == "sans rien"

    # pri hors A-Z / sur numéro absent
    assert {:error, m} = CLI.run(["pri", "1", "AA"], e)
    assert m =~ "invalid priority"
    assert {:error, m} = CLI.run(["append", "9", "x"], e)
    assert m =~ "no task 9"
    assert {:usage, _} = CLI.run(["append", "1"], e)
  end

  # ---------------------------------------------------------------------
  # 6. Aller-retour todo/done
  # ---------------------------------------------------------------------

  test "aller-retour todo/done : mv, undo, do, archive restent cohérents", %{env: e} do
    {:ok, _} = CLI.run(["add", "alpha +a"], e)
    {:ok, _} = CLI.run(["add", "beta +b"], e)
    {:ok, _} = CLI.run(["add", "gamma +c"], e)

    # mv 1 done : la tâche OUVERTE est déplacée telle quelle (pas marquée x)
    assert {:ok, "1: moved to done"} = CLI.run(["mv", "1", "done"], e)
    assert raws(e.paths.todo) == ["2026-09-21 beta +b", "2026-09-21 gamma +c"]
    assert raws(e.paths.done) == ["2026-09-21 alpha +a"]
    # Limite constatée : mv ne complète pas la tâche — done.txt peut donc
    # contenir une ligne sans `x` (le format todo.txt ne l'interdit pas).
    {:ok, [d]} = Store.read(e.paths.done)
    refute d.done

    # Les numéros de todo.txt sont renumérotés : beta est maintenant 1
    {:ok, ts} = Store.read(e.paths.todo)
    assert Enum.map(ts, &{&1.line, &1.description}) == [{1, "beta +b"}, {2, "gamma +c"}]

    # do 1 (beta) puis mv 1 done : arrive dans done.txt avec son x
    {:ok, _} = CLI.run(["do", "1"], e)
    assert {:ok, "1: moved to done"} = CLI.run(["mv", "1", "done"], e)
    assert raws(e.paths.done) == ["2026-09-21 alpha +a", "x 2026-09-21 2026-09-21 beta +b"]
    assert raws(e.paths.todo) == ["2026-09-21 gamma +c"]

    # mv 2 todo : le numéro est celui de done.txt ; la tâche arrive en fin de todo.txt
    assert {:ok, "2: moved to todo"} = CLI.run(["mv", "2", "todo"], e)
    assert raws(e.paths.done) == ["2026-09-21 alpha +a"]
    assert raws(e.paths.todo) == ["2026-09-21 gamma +c", "x 2026-09-21 2026-09-21 beta +b"]

    # undo 2 : beta redevient ouverte, sa date de complétion disparaît
    assert {:ok, "2: 2026-09-21 beta +b"} = CLI.run(["undo", "2"], e)
    t = by_line(e.paths.todo, 2)
    refute t.done
    assert t.completion_date == nil and t.creation_date == @today

    # mv 1 todo ramène alpha ; ls voit les trois, listall voit done.txt vide
    assert {:ok, "1: moved to todo"} = CLI.run(["mv", "1", "todo"], e)
    assert {:ok, []} = Store.read(e.paths.done)

    assert raws(e.paths.todo) == [
             "2026-09-21 gamma +c",
             "2026-09-21 beta +b",
             "2026-09-21 alpha +a"
           ]

    # do + archive : chemin standard ; undo sur une ligne ouverte est un no-op
    {:ok, _} = CLI.run(["do", "3"], e)
    assert {:ok, "1: 2026-09-21 gamma +c"} = CLI.run(["undo", "1"], e)
    {:ok, _} = CLI.run(["archive"], e)
    assert raws(e.paths.done) == ["x 2026-09-21 2026-09-21 alpha +a"]
    assert length(raws(e.paths.todo)) == 2

    # Numéros invalides sur les deux fichiers
    assert {:error, m} = CLI.run(["mv", "7", "done"], e)
    assert m =~ "no task 7"
    assert {:error, m} = CLI.run(["mv", "2", "todo"], e)
    assert m =~ "no task 2"
    assert {:error, _} = CLI.run(["undo", "x"], e)
  end

  # ---------------------------------------------------------------------
  # 7. Robustesse fichiers
  # ---------------------------------------------------------------------

  test "robustesse : sans newline finale, lignes vides, CRLF, dedupe", %{env: e} do
    # Pas de newline finale + lignes vides intercalées + CRLF
    File.write!(e.paths.todo, "un\n\n\ndeux +p\r\n\n   \nun\ntrois")

    # Les numéros de ligne sont physiques : les lignes vides comptent
    {:ok, ts} = Store.read(e.paths.todo)

    assert Enum.map(ts, &{&1.line, &1.raw}) == [
             {1, "un"},
             {4, "deux +p"},
             {7, "un"},
             {8, "trois"}
           ]

    # ls affiche ces numéros ; la tâche 7 est adressable
    assert {:ok, out} = CLI.run(["--plain", "ls"], e)
    assert lines(out) == ["1: un", "4: deux +p", "7: un", "8: trois"]
    assert {:ok, "7: (C) un"} = CLI.run(["pri", "7", "C"], e)

    # pri a réécrit le fichier compacté : lignes vides et CRLF disparaissent
    assert File.read!(e.paths.todo) == "un\ndeux +p\n(C) un\ntrois\n"

    # add sur un fichier sans newline finale la répare et numérote correctement
    File.write!(e.paths.todo, "un\ndeux")
    assert {:ok, "3: 2026-09-21 trois"} = CLI.run(["add", "trois"], e)
    assert File.read!(e.paths.todo) == "un\ndeux\n2026-09-21 trois\n"

    # dedupe : comparaison sur le raw, la 1re occurrence gagne
    File.write!(e.paths.todo, "same +p\nother\nsame +p\n\nsame +p\nSame +p\n")
    assert {:ok, "removed 2 duplicates"} = CLI.run(["dedupe"], e)
    assert raws(e.paths.todo) == ["same +p", "other", "Same +p"]
    assert {:ok, "removed 0 duplicates"} = CLI.run(["dedupe"], e)

    # Fichiers absents : lectures vides, pas d'erreur
    File.rm!(e.paths.todo)
    assert {:ok, ""} = CLI.run(["--plain", "ls"], e)
    assert {:ok, "[]"} = CLI.run(["--json", "ls"], e)
    assert {:ok, "archived 0 tasks"} = CLI.run(["archive"], e)
    refute File.exists?(e.paths.done)
  end

  test "robustesse : atomicité de mv et archive sur échec d'append", %{env: e} do
    File.write!(e.paths.todo, "one\nx two\nthree\n")
    File.write!(e.paths.done, "")
    # done.txt.tmp en tant que répertoire fait échouer l'append atomique
    File.mkdir_p!(e.paths.done <> ".tmp")

    assert {:error, m} = CLI.run(["mv", "1", "done"], e)
    assert m =~ "cannot write"
    assert raws(e.paths.todo) == ["one", "x two", "three"]
    assert {:ok, []} = Store.read(e.paths.done)

    # archive : même garantie — todo.txt intact tant que l'append a échoué
    assert {:error, _} = CLI.run(["archive"], e)
    assert raws(e.paths.todo) == ["one", "x two", "three"]

    # Le répertoire retiré, les mêmes commandes réussissent
    File.rmdir!(e.paths.done <> ".tmp")
    assert {:ok, "archived 1 tasks"} = CLI.run(["archive"], e)
    assert raws(e.paths.todo) == ["one", "three"]
    assert raws(e.paths.done) == ["x two"]
  end

  test "robustesse : todo.txt illisible remonte une erreur sans écrire", %{env: e} do
    File.mkdir_p!(e.paths.todo)
    assert {:error, m} = CLI.run(["add", "x"], e)
    assert m =~ "cannot read"
    assert {:error, _} = CLI.run(["ls"], e)
    assert File.dir?(e.paths.todo)
  end

  # ---------------------------------------------------------------------
  # 8. Parsing limite
  # ---------------------------------------------------------------------

  test "parsing limite : priorité + date, URL non-tag, dates de complétion", %{env: e} do
    assert {:ok, out} = CLI.run(["add", "(A) lire https://example.com/a:b?x=1 +web"], e)
    assert out == "1: (A) 2026-09-21 lire https://example.com/a:b?x=1 +web"
    t = by_line(e.paths.todo, 1)
    assert t.priority == ?A and t.creation_date == @today
    assert t.description == "lire https://example.com/a:b?x=1 +web"
    # Un token contenant :// n'est pas un tag clé:valeur
    assert t.tags == %{}
    assert t.projects == ["+web"]

    # Un tag mail:, port: ... reste un tag ; une clé avec tiret aussi
    {:ok, _} = CLI.run(["add", "mail:a@b.c ping:1.2.3.4:22 x-key:v @ctx"], e)
    t = by_line(e.paths.todo, 2)
    assert t.tags == %{"mail" => "a@b.c", "ping" => "1.2.3.4:22", "x-key" => "v"}
    # `a@b.c` fait partie du token mail:... → pas un contexte
    assert t.contexts == ["@ctx"]

    # Une priorité en milieu de ligne n'en est pas une ; `+` / `@` seuls non plus
    {:ok, _} = CLI.run(["add", "note (B) pas prio + @ +ok"], e)
    t = by_line(e.paths.todo, 3)
    assert t.priority == nil and t.projects == ["+ok"] and t.contexts == []

    # Priorité minuscule ou (AA) : pas reconnue, reste dans la description
    {:ok, _} = CLI.run(["add", "(a) minuscule"], e)
    {:ok, _} = CLI.run(["add", "(AA) double"], e)
    assert by_line(e.paths.todo, 4).priority == nil
    assert by_line(e.paths.todo, 4).raw == "2026-09-21 (a) minuscule"
    assert by_line(e.paths.todo, 5).priority == nil

    # do : `x` + date de complétion + date de création, priorité retirée
    assert {:ok, out} = CLI.run(["do", "1"], e)
    assert out == "1: x 2026-09-21 2026-09-21 lire https://example.com/a:b?x=1 +web"
    t = by_line(e.paths.todo, 1)
    assert t.done and t.completion_date == @today and t.creation_date == @today
    assert t.priority == nil
    # Limite : la priorité n'est pas conservée en `pri:A` après complétion
    # (extension todo.sh non implémentée).
    refute Map.has_key?(t.tags, "pri")

    # undo : la priorité perdue ne revient pas
    assert {:ok, "1: 2026-09-21 lire https://example.com/a:b?x=1 +web"} =
             CLI.run(["undo", "1"], e)

    # Ligne écrite à la main : `x` + création seule (pas de date de complétion)
    File.write!(e.paths.todo, "x 2026-09-10 sans complétion\nx (A) prio après x\n")
    {:ok, [a, b]} = Store.read(e.paths.todo)
    # Limite : la 1re date après `x` est lue comme date de complétion,
    # conformément au format (completion puis création).
    assert a.done and a.completion_date == ~D[2026-09-10] and a.creation_date == nil
    # (A) après x n'est pas une priorité : la description la conserve
    assert b.done and b.priority == nil and b.description == "(A) prio après x"
    assert {:error, _} = CLI.run(["pri", "2", "B"], e)

    # do sur une ligne déjà faite : re-complétée à today (pas d'erreur)
    assert {:ok, "1: x 2026-09-21 sans complétion"} = CLI.run(["do", "1"], e)

    # Date de création invalide (mois 13) : token gardé dans la description
    File.write!(e.paths.todo, "(B) 2026-13-01 date invalide\n")
    {:ok, [t]} = Store.read(e.paths.todo)
    assert t.priority == ?B and t.creation_date == nil
    assert t.description == "2026-13-01 date invalide"
  end
end
