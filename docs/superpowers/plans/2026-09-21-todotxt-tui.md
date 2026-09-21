# TUI term_ui pour todotxt — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter un TUI interactif complet (`todo --tui`) au-dessus du CLI existant, via `term_ui ~> 1.0`, en extrayant une couche `TodoTxt.Ops` partagée.

**Architecture:** `TodoTxt.Ops` = opérations pures sur `[%Task{}]` extraites des `Commands.*` (qui deviennent des coquilles formatage). `TodoTxt.Tui` = app Elm term_ui (`init/event_to_msg/update/view`) avec layout 3 panes (sidebar filtres / liste / détail), modales widgets (TextInput, PickList, AlertDialog), watch mtime 2 s, et boucle quit→`$EDITOR`→relaunch pour `E`.

**Tech Stack:** Elixir ~> 1.18, escript, term_ui ~> 1.0 (publié 2026-08-31 ; API : `use TermUI.Elm`, `Event.Key`, `Command.timer/interval/quit`, `TermUI.Widgets.{TextInput,AlertDialog,Toast}`, `TermUI.Widget.PickList` — singulier), ExUnit.

**Spec:** `docs/superpowers/specs/2026-09-21-todotxt-tui-design.md`

## Global Constraints

- `{:term_ui, "~> 1.0"}` dans `mix.exs` — jamais de `latest`/`*`
- `System.halt` uniquement dans `TodoTxt.CLI.main/1`
- Toute écriture de fichier via `Store.write/2`, `Store.append/2` (write_atomic) — jamais `File.write` direct
- Numérotation des tâches = `task.line` (numéro de ligne fichier)
- Comportement CLI inchangé : la suite existante (`mix test`) reste verte sans modification de tests commands/cli
- `mix format` propre ; commits fréquents après chaque étape verte
- Convention repo : commits en français/anglais type conventional, identité git via env vars (`GIT_AUTHOR_NAME=Devin`, `GIT_AUTHOR_EMAIL=devin@cognition.ai`, idem committer) — ne jamais toucher `git config`

## Review Focus

1. **Modale ouverte + reload externe** supprime/remplace la tâche ciblée : le submit doit retomber sur `{:error, _}` → toast, jamais de crash — testé en T7.
2. **`recur:` malformé** au `x` : `Ops.complete` rend `{:error, _}` avant toute écriture (parité `Commands.Do`) — testé en T1.
3. **todo.txt illisible au lancement** de `--tui` : erreur stderr + exit 1 façon CLI, le runtime ne démarre pas — testé en T3.
4. **`$EDITOR` absent ou exit non-zéro** : message `todo:` propre, pas de stacktrace, pas de TUI zombie — testé en T9.
5. **Filtre actif + liste raccourcie** (reload, archive) : `list_idx` est clampé, jamais d'index hors bornes — testé en T4/T6.
6. **mtime identique, contenu différent** (granularité fs) : non détecté — `r` reste le recours manuel documenté.

---

### Task 1: `TodoTxt.Ops` — opérations pures partagées

**Files:**
- Create: `lib/todotxt/ops.ex`
- Test: `test/todotxt/ops_test.exs`

**Interfaces:**
- Consumes: `TodoTxt.{Task, Parser, Commands.Helpers}` (`Helpers.replace/2`)
- Produces (utilisé par T2, T6) :

```elixir
Ops.add(tasks, text, today)            :: %Task{}          # ligne = max+1, date insérée
Ops.next_line(tasks)                   :: non_neg_integer()
Ops.complete(tasks, %Task{}=t, today)  :: {:ok, tasks', recur | nil} | {:error, msg}
Ops.uncomplete(tasks, %Task{}=t)       :: {:ok, tasks'}
Ops.delete(tasks, %Task{}=t)           :: {:ok, tasks'}
Ops.delete_term(tasks, %Task{}=t, term):: {:ok, tasks'}
Ops.set_priority(tasks, %Task{}=t, c)  :: {:ok, tasks'} | {:error, msg}  # c = ?A..?Z | nil
Ops.replace_text(tasks, %Task{}=t, txt):: {:ok, tasks'}    # Parser.parse(txt, t.line)
Ops.append_text(tasks, %Task{}=t, txt) :: {:ok, tasks'}
Ops.prepend_text(tasks, %Task{}=t, txt):: {:ok, tasks'}
Ops.archive(tasks)                     :: {open, done}
Ops.dedupe(tasks)                      :: tasks'
Ops.agenda(tasks, today)               :: {[{Date.t(), [Task.t()]}], [Task.t()]}
```

- [ ] **Step 1: Écrire les tests `ops_test.exs` (cycle vie + texte)**

```elixir
defmodule TodoTxt.OpsTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Ops, Parser}

  defp t(raw, line), do: Parser.parse(raw, line)
  @today ~D[2026-09-21]

  test "add assigns max+1 line and inserts creation date" do
    tasks = [t("a", 1), t("b", 5)]
    new = Ops.add(tasks, "call mom +fam", @today)
    assert new.line == 6
    assert new.raw == "2026-09-21 call mom +fam"
    assert new.creation_date == @today
  end

  test "add keeps (A) priority before the date" do
    new = Ops.add([], "(A) urgent", @today)
    assert new.raw == "(A) 2026-09-21 urgent"
  end

  test "complete marks done, drops priority, returns no recur" do
    tasks = [t("(A) 2026-09-01 x +p", 3)]
    assert {:ok, [done], nil} = Ops.complete(tasks, hd(tasks), @today)
    assert done.done and done.completion_date == @today and done.priority == nil
  end

  test "complete spawns next recurrence with line max+1" do
    tasks = [t("pay rent +home due:2026-09-30 recur:+1m", 2), t("other", 9)]
    assert {:ok, _tasks, recur} = Ops.complete(tasks, hd(tasks), @today)
    assert recur.tags["due"] == "2026-10-30"
    assert recur.done == false
  end

  test "complete with malformed recur errors before mutating" do
    tasks = [t("x recur:banana", 1)]
    assert {:error, msg} = Ops.complete(tasks, hd(tasks), @today)
    assert msg =~ "invalid recur"
  end

  test "uncomplete clears done and completion date" do
    tasks = [t("x 2026-09-20 done thing", 4)]
    assert {:ok, [t2]} = Ops.uncomplete(tasks, hd(tasks))
    refute t2.done
    assert t2.completion_date == nil
  end

  test "delete removes the task; delete_term strips the token" do
    tasks = [t("a +p @c", 1), t("b", 2)]
    assert {:ok, [left]} = Ops.delete(tasks, hd(tasks))
    assert left.line == 2
    assert {:ok, [stripped, _]} = Ops.delete_term(tasks, hd(tasks), "+p")
    assert stripped.description == "a @c"
  end

  test "set_priority validates A-Z and rejects done tasks" do
    t1 = t("open", 1)
    assert {:ok, [p]} = Ops.set_priority([t1], t1, ?B)
    assert p.priority == ?B
    assert {:error, _} = Ops.set_priority([t1], t1, ?a)
    done = t("x done", 2)
    assert {:error, msg} = Ops.set_priority([done], done, ?A)
    assert msg =~ "already done"
  end

  test "replace_text reparses the full line" do
    tasks = [t("old", 7)]
    assert {:ok, [new]} = Ops.replace_text(tasks, hd(tasks), "(C) 2026-01-01 new +proj")
    assert new.line == 7 and new.priority == ?C and "+proj" in new.projects
  end

  test "append_text and prepend_text" do
    tasks = [t("base @c", 1)]
    assert {:ok, [a]} = Ops.append_text(tasks, hd(tasks), "tail due:2026-10-01")
    assert a.description =~ "tail due:2026-10-01"
    assert {:ok, [p]} = Ops.prepend_text(tasks, hd(tasks), "head")
    assert p.description =~ ~r/^head base/
  end

  test "archive splits done; dedupe keeps first occurrence" do
    tasks = [t("x done1", 1), t("open", 2), t("open", 3)]
    assert {open, done} = Ops.archive(tasks)
    assert Enum.map(open, & &1.line) == [2, 3]
    assert length(done) == 1
    assert Enum.map(Ops.dedupe(tasks), & &1.line) == [1, 2]
  end

  test "agenda groups open tasks by due date within 14 days + thresholds" do
    tasks = [
      t("overdue due:2026-09-01", 1),
      t("soon due:2026-09-25", 2),
      t("far due:2027-01-01", 3),
      t("x done due:2026-09-22", 4),
      t("hidden t:2026-09-30", 5)
    ]
    {groups, thresholds} = Ops.agenda(tasks, @today)
    assert Enum.map(groups, fn {d, ts} -> {d, Enum.map(ts, & &1.line)} end) ==
             [{~D[2026-09-25], [2]}]
    assert Enum.map(thresholds, & &1.line) == [5]
  end
end
```

- [ ] **Step 2: Vérifier l'échec** — `mix test test/todotxt/ops_test.exs` → `undefined module TodoTxt.Ops`

- [ ] **Step 3: Écrire `lib/todotxt/ops.ex`**

```elixir
defmodule TodoTxt.Ops do
  @moduledoc """
  Pure task-list operations shared by `TodoTxt.Commands.*` (CLI) and
  `TodoTxt.Tui`. No I/O, no output strings — callers write via
  `Store` and format their own feedback.
  """

  alias TodoTxt.{Commands.Helpers, Parser, Query, Task}

  @days 14

  @doc "Next free line number (`max(line) + 1`, 1 on empty list)."
  def next_line(tasks), do: (tasks |> Enum.map(& &1.line) |> Enum.max(fn -> 0 end)) + 1

  @doc "New task appended at `next_line/1`, creation date = today (after a leading `(X)`)."
  @spec add([Task.t()], String.t(), Date.t()) :: Task.t()
  def add(tasks, text, today), do: Parser.parse(with_date(text, today), next_line(tasks))

  defp with_date(text, today) do
    date = Date.to_string(today)

    case String.split(text, ~r/\s+/, trim: true) do
      [first | rest] ->
        if Regex.match?(~r/^\([A-Z]\)$/, first),
          do: Enum.join([first, date | rest], " "),
          else: Enum.join([date, first | rest], " ")

      [] ->
        date
    end
  end

  @doc """
  Mark `t` done today. Returns `{new_tasks, recur}` where `recur` is the
  next occurrence (line still 0 — caller assigns `next_line/1`) or nil.
  A present-but-malformed `recur:` tag is an error; nothing mutates.
  """
  @spec complete([Task.t()], Task.t(), Date.t()) ::
          {:ok, [Task.t()], Task.t() | nil} | {:error, String.t()}
  def complete(tasks, t, today) do
    case t.tags["recur"] do
      nil ->
        finish_complete(tasks, t, today)

      v ->
        if Task.next_recurrence(t, today) do
          finish_complete(tasks, t, today)
        else
          {:error, "invalid recur: #{inspect(v)} on task #{t.line}"}
        end
    end
  end

  defp finish_complete(tasks, t, today) do
    {:ok, Helpers.replace(tasks, Task.complete(t, today)), Task.next_recurrence(t, today)}
  end

  @spec uncomplete([Task.t()], Task.t()) :: {:ok, [Task.t()]}
  def uncomplete(tasks, t), do: {:ok, Helpers.replace(tasks, Task.uncomplete(t))}

  @spec delete([Task.t()], Task.t()) :: {:ok, [Task.t()]}
  def delete(tasks, t), do: {:ok, Enum.reject(tasks, &(&1.line == t.line))}

  @doc "Strip every whitespace-separated `term` token from `t`'s description."
  @spec delete_term([Task.t()], Task.t(), String.t()) :: {:ok, [Task.t()]}
  def delete_term(tasks, t, term) do
    desc = t.description |> String.split(~r/\s+/) |> Enum.reject(&(&1 == term)) |> Enum.join(" ")
    {:ok, Helpers.replace(tasks, Task.set_text(t, desc))}
  end

  @doc "Set priority `?A..?Z`, or nil to remove. Errors on done tasks / bad input."
  @spec set_priority([Task.t()], Task.t(), non_neg_integer() | nil) ::
          {:ok, [Task.t()]} | {:error, String.t()}
  def set_priority(tasks, t, nil), do: {:ok, Helpers.replace(tasks, Task.set_priority(t, nil))}

  def set_priority(tasks, t, c) when is_integer(c) do
    cond do
      c not in ?A..?Z -> {:error, "invalid priority #{inspect(<<c>>)} (A-Z)"}
      t.done -> {:error, "task #{t.line} is already done"}
      true -> {:ok, Helpers.replace(tasks, Task.set_priority(t, c))}
    end
  end

  @doc "Replace `t`'s whole line — reparsed, so `x`/`(A)`/dates are honored."
  @spec replace_text([Task.t()], Task.t(), String.t()) :: {:ok, [Task.t()]}
  def replace_text(tasks, t, text),
    do: {:ok, Helpers.replace(tasks, Parser.parse(text, t.line))}

  @spec append_text([Task.t()], Task.t(), String.t()) :: {:ok, [Task.t()]}
  def append_text(tasks, t, text),
    do: {:ok, Helpers.replace(tasks, Task.append_text(t, text))}

  @spec prepend_text([Task.t()], Task.t(), String.t()) :: {:ok, [Task.t()]}
  def prepend_text(tasks, t, text),
    do: {:ok, Helpers.replace(tasks, Task.prepend_text(t, text))}

  @doc "`{open, done}` — done tasks to append to done.txt, open to rewrite."
  @spec archive([Task.t()]) :: {[Task.t()], [Task.t()]}
  def archive(tasks), do: tasks |> Enum.split_with(& &1.done) |> then(fn {d, o} -> {o, d} end)

  @spec dedupe([Task.t()]) :: [Task.t()]
  def dedupe(tasks), do: Enum.uniq_by(tasks, & &1.raw)

  @doc """
  `{groups, thresholds}` for the next #{@days} days: open tasks grouped by
  `due:` (sorted by date), then open tasks whose `t:` falls in the window.
  Overdue and done tasks are excluded — same data as `Commands.Agenda`.
  """
  @spec agenda([Task.t()], Date.t()) :: {[{Date.t(), [Task.t()]}], [Task.t()]}
  def agenda(tasks, today) do
    horizon = Date.add(today, @days)
    open = Enum.reject(tasks, & &1.done)
    in_range? = fn d ->
      not is_nil(d) and Date.compare(d, today) != :lt and Date.compare(d, horizon) != :gt
    end

    groups =
      open
      |> Enum.group_by(&Query.due_date/1)
      |> Enum.reject(fn {d, _} -> not in_range?.(d) end)
      |> Enum.sort_by(fn {d, _} -> d end, Date)

    thresholds =
      open
      |> Enum.filter(&in_range?.(threshold_date(&1)))
      |> Enum.sort_by(& &1.line)

    {groups, thresholds}
  end

  defp threshold_date(t) do
    case t.tags["t"] && Date.from_iso8601(t.tags["t"]) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
```

- [ ] **Step 4: Vérifier** — `mix test test/todotxt/ops_test.exs` → vert

- [ ] **Step 5: Commit**

```bash
git add lib/todotxt/ops.ex test/todotxt/ops_test.exs
git commit -m "feat: TodoTxt.Ops — opérations pures partagées CLI/TUI"
```

---

### Task 2: Refactor `Commands.*` → `Ops`

**Files:**
- Modify: `lib/todotxt/commands/{add,do,undo,del,pri,depri,append,prepend,replace,move,archive,dedupe,agenda}.ex`
- Test: suite existante (aucune modif de test)

**Interfaces:**
- Consumes: `TodoTxt.Ops` (T1)
- Produces: inchangé — contrat `run(args, ctx) :: {:ok|:error|:usage, msg}`

- [ ] **Step 1: Refactorer les commandes lifecycle**

`commands/do.ex` :

```elixir
def run([n | _], %{tasks: tasks, paths: paths, today: today}) do
  with {:ok, t} <- Helpers.fetch(tasks, n),
       {:ok, tasks2, recur} <- Ops.complete(tasks, t, today),
       :ok <- Store.write(paths.todo, tasks2),
       {:ok, note} <- append_recurrence(recur, tasks, paths) do
    done = Task.complete(t, today)
    {:ok, "#{t.line}: #{Parser.render(done)}#{note}"}
  end
end

defp append_recurrence(nil, _tasks, _paths), do: {:ok, ""}

defp append_recurrence(new, tasks, paths) do
  new = %{new | line: Ops.next_line(tasks)}

  case Store.append(paths.todo, [new]) do
    :ok -> {:ok, "\n#{new.line}: #{Parser.render(new)}"}
    {:error, m} -> {:error, m}
  end
end
```

`commands/undo.ex` — `with {:ok, t} <- fetch, {:ok, ts} <- Ops.uncomplete(tasks, t), :ok <- Store.write(paths.todo, ts), do: {:ok, "#{t.line}: #{Parser.render(Task.uncomplete(t))}"}`

`commands/del.ex` — `nil` term: `{:ok, ts} <- Ops.delete(tasks, t)` ; term: `Ops.delete_term(tasks, t, term)` (message identique).

`commands/pri.ex` — garder `valid_priority(t, p)` pour le message exact (« invalid priority … (A-Z) »), puis `Ops.set_priority(tasks, t, :binary.first(p))`. `depri.ex` → `Ops.set_priority(tasks, t, nil)`.

`commands/{append,prepend}.ex` → `Ops.append_text/3`, `Ops.prepend_text/3`. `replace.ex` → `Ops.replace_text(tasks, t, Enum.join(words, " "))`.

`commands/add.ex` → `task = Ops.add(tasks, Enum.join(words, " "), today)` puis `Store.append` ; supprimer `with_date/2` local.

`commands/move.ex` → `{:ok, t} <- fetch, :ok <- Store.append(dest, [t]), {:ok, ts} <- Ops.delete(tasks, t), :ok <- Store.write(src, ts)` (ordre append-avant-write conservé).

`commands/archive.ex` → `{open, done} = Ops.archive(tasks)` ; `append_done` inchangé. `dedupe.ex` → `Ops.dedupe(tasks)`. `agenda.ex` → `{groups, thresholds} = Ops.agenda(tasks, today)` (supprimer la logique dupliquée, garder le formatage texte/JSON).

- [ ] **Step 2: Suite complète** — `mix test` → tout vert (non-régression)

- [ ] **Step 3: `mix format --check-formatted`** — corriger si besoin

- [ ] **Step 4: Commit**

```bash
git add lib/todotxt/commands/
git commit -m "refactor: Commands délèguent à TodoTxt.Ops (comportement inchangé)"
```

---

### Task 3: `--tui` flag + `Tui.run` squelette

**Files:**
- Modify: `mix.exs` (deps), `lib/todotxt/cli.ex` (@switches + dispatch), `lib/todotxt/commands/help.ex` (ligne tui)
- Create: `lib/todotxt/tui.ex`
- Test: `test/todotxt/cli_test.exs` (ajout)

**Interfaces:**
- Produces (consommé par T5-T9) :

```elixir
TodoTxt.Tui.run(env) :: {:ok, nil} | {:error, msg}
# env = %{paths:, tasks:, done_tasks:, today:, opts:, caller: pid, io: map, runner: fun}
```

- [ ] **Step 1: Test dispatch dans `cli_test.exs`**

```elixir
test "--tui dispatches to Tui.run and returns its result" do
  test_pid = self()

  env = %{
    paths: %{todo: "t.txt", done: "d.txt", report: "r.txt"},
    tasks: [],
    done_tasks: [],
    today: ~D[2026-09-21],
    runner: fn env -> send(test_pid, {:tui_ran, env.paths.todo}) && {:ok, nil} end
  }

  assert {:ok, nil} = TodoTxt.CLI.run(["--tui"], env)
  assert_received {:tui_ran, "t.txt"}
end

test "--tui rejects extra args" do
  assert {:usage, _} = TodoTxt.CLI.run(["--tui", "ls"], %{today: ~D[2026-09-21]})
end
```

- [ ] **Step 2: Vérifier échec** — `mix test test/todotxt/cli_test.exs` → usage/unknown option

- [ ] **Step 3: Implémenter**

`mix.exs` deps : `[{:jason, "~> 1.4"}, {:term_ui, "~> 1.0"}]` puis `mix deps.get`.

`cli.ex` : ajouter `tui: :boolean` à `@switches` ; dans `run_command/2`, avant le dispatch commandes :

```elixir
if kw[:tui] do
  case rest do
    [] ->
      with {:ok, tasks} <- Store.read(env.paths.todo),
           {:ok, done} <- Store.read(env.paths.done) do
        env = Map.merge(env, %{tasks: tasks, done_tasks: done})
        TodoTxt.Tui.run(env)
      end

    _ ->
      {:usage, "--tui takes no command"}
  end
else
  # dispatch existant inchangé
end
```

`help.ex` : ajouter la ligne `--tui` dans le texte d'aide.

`lib/todotxt/tui.ex` (squelette — T5-T9 le complètent) :

```elixir
defmodule TodoTxt.Tui do
  @moduledoc "Interactive TUI — `todo --tui`. Elm app on term_ui."
  use TermUI.Elm

  alias TodoTxt.Tui.State
  alias TermUI.Command

  @doc "Runs the TUI; loops for external $EDITOR sessions. Returns {:ok, nil} | {:error, msg}."
  def run(env) do
    env =
      env
      |> Map.put_new(:today, Date.utc_today())
      |> Map.put_new(:io, %{
        read: &TodoTxt.Store.read/1, write: &TodoTxt.Store.write/2,
        append: &TodoTxt.Store.append/2, stat: &File.stat/1
      })
      |> Map.put(:caller, self())

    runner = env[:runner] || fn e -> TermUI.Runtime.run(root: __MODULE__, env: e) end

    case runner.(env) do
      :ok -> handle_exit(env)
      {:error, m} -> {:error, m}
    end
  end

  defp handle_exit(env) do
    receive do
      {:tui_exit, :edit} ->
        case edit_external(env) do
          :ok -> run(env)
          {:error, m} -> {:error, m}
        end

      _ ->
        {:ok, nil}
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

  # --- Elm callbacks (T5+ complète ; squelette autonome, sans State) ---
  def init(opts) do
    env = Keyword.fetch!(opts, :env)
    {:ok, %{env: env}, [Command.interval(2_000, :tick)]}
  end

  def event_to_msg(_, _), do: :ignore
  def update(_, state), do: {state, []}
  def view(_), do: text("todo --tui")
  def handle_info(msg, state), do: update(msg, state)
end
```

- [ ] **Step 4: Vérifier** — `mix test` → vert

- [ ] **Step 5: Commit** — `git commit -m "feat: flag --tui + squelette Tui.run (boucle edit)"`

---

### Task 4: `Tui.State` — modèle, sidebar, vues, sélection

**Files:**
- Create: `lib/todotxt/tui/state.ex`
- Test: `test/todotxt/tui/state_test.exs`

**Interfaces:**
- Produces (consommé par T5/T6/T8) :

```elixir
State.new(env)                       :: %State{}
State.sidebar_entries(state)         :: [entry]
# entry = {:header, String.t()} | {:all, label} | {:project|:context, label, term}
#       | {:view, label, :agenda | :done}
State.rows(state)                    :: [row]        # row = {:header, String.t()} | {:task, Task.t()}
State.selected_task(state)           :: Task.t() | nil
State.move_cursor(state, delta)      :: %State{}     # clamp, saute les :header
State.activate_sidebar(state)        :: %State{}     # toggle term ou switch view
State.counts(state)                  :: %{open: n, done: n}
State.mtime(io, path)                :: term | nil
State.refresh_mtimes(state)          :: %State{}
```

- [ ] **Step 1: Tests `state_test.exs`**

```elixir
defmodule TodoTxt.Tui.StateTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Parser, Tui.State}

  defp st(tasks, done \\ [], opts \\ []) do
    State.new(%{
      paths: %{todo: "t", done: "d", report: "r"},
      tasks: tasks, done_tasks: done, today: ~D[2026-09-21],
      io: fake_io(), caller: self()
    })
    |> struct!(opts)
  end

  defp fake_io do
    %{read: fn _ -> {:ok, []} end, write: fn _, _ -> :ok end,
      append: fn _, _ -> :ok end, stat: fn _ -> {:error, :enoent} end}
  end

  defp t(raw, line), do: Parser.parse(raw, line)

  test "sidebar lists projects and contexts with counts, then views" do
    s = st([t("a +p1 @c1", 1), t("b +p1 @c2", 2), t("c +p2", 3)])
    entries = State.sidebar_entries(s)
    labels = Enum.map(entries, &elem(&1, 1))
    assert "── Projets ──" in labels and "── Contextes ──" in labels
    assert Enum.find(entries, &match?({:project, "+p1 (2)", "+p1"}, &1))
    assert Enum.find(entries, &match?({:context, "@c2 (1)", "@c2"}, &1))
    assert {:view, "Agenda", :agenda} in entries
    assert {:view, "Done", :done} in entries
  end

  test "rows in :todo are visible+filtered+sorted; done hidden by t:" do
    s = st([t("b", 2), t("(A) a", 1), t("hidden t:2999-01-01", 3)])
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [1, 2]
    s = %{s | filter_terms: ["b"]}
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [2]
  end

  test "rows in :done show done.txt newest last-appended first" do
    s = st([], [t("x old", 1), t("x new", 2)], view: :done)
    assert Enum.map(State.rows(s), fn {:task, t} -> t.line end) == [2, 1]
  end

  test "rows in :agenda emit date headers and threshold section" do
    s = st([t("soon due:2026-09-25", 1), t("t t:2026-09-30", 2)], view: :agenda)
    rows = State.rows(s)
    assert {:header, "2026-09-25:"} in rows
    assert {:header, "THRESHOLDS:"} in rows
  end

  test "move_cursor clamps and skips headers" do
    s = st([t("a", 1), t("b", 2)])
    assert State.move_cursor(s, -1).list_idx == 0
    assert State.move_cursor(s, 5).list_idx == 1
  end

  test "activate_sidebar toggles project term; view entries switch view" do
    s = st([t("a +p", 1)])
    proj_idx = Enum.find_index(State.sidebar_entries(s), &match?({:project, _, _}, &1))
    s = %{s | sidebar_idx: proj_idx} |> State.activate_sidebar()
    assert s.filter_terms == ["+p"]
    s = State.activate_sidebar(s)
    assert s.filter_terms == []

    s = st([t("a", 1)])
    done_idx = Enum.find_index(State.sidebar_entries(s), &match?({:view, _, :done}, &1))
    s = %{s | sidebar_idx: done_idx} |> State.activate_sidebar()
    assert s.view == :done and s.list_idx == 0
  end

  test "selected_task follows list_idx over task rows" do
    s = st([t("a", 1), t("b", 2)], list_idx: 1)
    assert State.selected_task(s).line == 2
  end
end
```

- [ ] **Step 2: Vérifier échec** — `mix test test/todotxt/tui/state_test.exs`

- [ ] **Step 3: Écrire `state.ex`**

```elixir
defmodule TodoTxt.Tui.State do
  @moduledoc "Pure TUI model: cursor, filters, views, sidebar. No rendering."

  alias TodoTxt.{Ops, Query}

  defstruct paths: nil, today: nil, tasks: [], done_tasks: [],
            view: :todo, focus: :list, sidebar_idx: 0, list_idx: 0,
            filter_terms: [], mode: :normal, modal: nil,
            toasts: [], mtimes: %{}, status: nil,
            width: 80, height: 24, caller: nil, io: nil

  def new(env) do
    %__MODULE__{
      paths: env.paths, today: env.today,
      tasks: env.tasks || [], done_tasks: env.done_tasks || [],
      caller: env.caller, io: env.io,
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
      {:all, _} -> %{s | view: :todo, filter_terms: [], list_idx: 0}
      {kind, _, term} when kind in [:project, :context] ->
        terms = if term in s.filter_terms, do: s.filter_terms -- [term], else: [term | s.filter_terms]
        %{s | view: :todo, filter_terms: terms, list_idx: 0}
      {:view, _, v} -> %{s | view: v, list_idx: 0}
      _ -> s
    end
  end

  def counts(s), do: %{open: Enum.count(s.tasks, &(not &1.done)), done: Enum.count(s.tasks, & &1.done)}

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
```

- [ ] **Step 4: Vérifier** — `mix test test/todotxt/tui/state_test.exs` → vert

- [ ] **Step 5: Commit** — `git commit -m "feat(tui): State — sidebar, vues, sélection"`

---

### Task 5: `Tui.Keys` + `event_to_msg` + navigation `update`

**Files:**
- Create: `lib/todotxt/tui/keys.ex`
- Modify: `lib/todotxt/tui.ex` (event_to_msg, update nav/focus/activate/quit)
- Test: `test/todotxt/tui_test.exs` (créer)

**Interfaces:**
- Produces : `Keys.msg(%Event.Key{}, mode :: :normal | :input) :: term | :ignore`

- [ ] **Step 1: Tests `tui_test.exs` — navigation et dispatch**

```elixir
defmodule TodoTxt.TuiTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Parser, Tui, Tui.State}
  alias TermUI.Event

  defp state(tasks, opts \\ []) do
    State.new(%{paths: %{todo: "t", done: "d", report: "r"}, tasks: tasks,
                done_tasks: [], today: ~D[2026-09-21], caller: self(), io: fake_io()})
    |> struct!(opts)
  end

  defp fake_io do
    %{read: fn _ -> {:ok, []} end, write: fn _, _ -> :ok end,
      append: fn _, _ -> :ok end, stat: fn _ -> {:error, :enoent} end}
  end

  defp t(raw, line), do: Parser.parse(raw, line)

  test "j/k move list cursor, arrows too" do
    s = state([t("a", 1), t("b", 2)])
    assert {:msg, {:nav, 1}} = Tui.event_to_msg(Event.key("j"), s)
    {s2, []} = Tui.update({:nav, 1}, s)
    assert s2.list_idx == 1
    {s3, []} = Tui.update({:nav, -1}, s2)
    assert s3.list_idx == 0
    assert {:msg, {:nav, 1}} = Tui.event_to_msg(Event.key(:down), s)
  end

  test "Tab toggles focus, Enter applies sidebar item" do
    s = state([t("a +p", 1)], focus: :sidebar)
    {s2, []} = Tui.update(:focus_next, s)
    assert s2.focus == :list
    {s3, []} = Tui.update(:focus_next, s2)
    assert s3.focus == :sidebar
  end

  test "q emits quit command" do
    s = state([])
    assert {:msg, :quit} = Tui.event_to_msg(Event.key("q"), s)
    {_s, cmds} = Tui.update(:quit, s)
    assert TermUI.Command.quit() in cmds or :quit in cmds
  end

  test "keys are ignored in :input mode except modal routing" do
    s = state([t("a", 1)], mode: :input, modal: %{action: :add, widget: nil})
    assert {:msg, {:modal_event, %Event.Key{key: "x"}}} =
             Tui.event_to_msg(Event.key("x"), s)
  end
end
```

(Note : les structs `%{State | field: v}` ne compilent pas dans un helper de test sur map générique — utiliser `Map.put` comme ci-dessus, ou `struct!/2` sur les champs connus.)

- [ ] **Step 2: Vérifier échec** — `mix test test/todotxt/tui_test.exs`

- [ ] **Step 3: `lib/todotxt/tui/keys.ex`**

```elixir
defmodule TodoTxt.Tui.Keys do
  @moduledoc "Keybinding table: Event.Key -> app message, per mode."

  alias TermUI.Event

  @normal %{
    :down => {:nav, 1}, :up => {:nav, -1},
    :tab => :focus_next, :enter => :activate, :escape => :clear_filter
  }

  @normal_chars %{
    "j" => {:nav, 1}, "k" => {:nav, -1},
    "h" => :focus_sidebar, "l" => :focus_list,
    "x" => :toggle_done, " " => :toggle_done,
    "a" => {:open_modal, :add}, "e" => {:open_modal, :edit},
    "A" => {:open_modal, :append}, "P" => {:open_modal, :prepend},
    "d" => {:open_modal, :del}, "p" => {:open_modal, :pri},
    "m" => :move, "R" => {:open_modal, :archive},
    "/" => {:open_modal, :filter},
    "E" => :edit_external, "r" => :reload, "?" => {:open_modal, :help},
    "q" => :quit
  }

  @doc "Translate a key event to a message for `mode`. :ignore when unbound."
  def msg(%Event.Key{key: key}, :normal) when is_atom(key),
    do: Map.get(@normal, key, :ignore)

  def msg(%Event.Key{key: key, modifiers: mods}, :normal) when is_binary(key),
    do: if(mods == [], do: Map.get(@normal_chars, key, :ignore), else: :ignore)

  def msg(%Event.Key{} = ev, :input), do: {:modal_event, ev}
  def msg(_, _), do: :ignore
end
```

- [ ] **Step 4: `tui.ex` — `init` réel, `event_to_msg` + handlers update navigation**

Remplacer l'`init` du squelette T3 par :

```elixir
def init(opts) do
  env = Keyword.fetch!(opts, :env)
  # Seed mtimes : sinon le 1er :tick (2 s) déclenche un reload parasite.
  state = State.new(env) |> State.refresh_mtimes()
  {:ok, state, [Command.interval(2_000, :tick)]}
end
```

Puis ajouter :

```elixir
alias TodoTxt.Tui.{Keys, State}
alias TermUI.Event

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

# Catch-all : messages inattendus (widget orphans, timers annulés) = no-op.
def update(_, s), do: {s, []}
```

- [ ] **Step 5: Vérifier** — `mix test test/todotxt/tui_test.exs` → vert ; `mix format`

- [ ] **Step 6: Commit** — `git commit -m "feat(tui): keys + navigation/focus/filtres"`

---

### Task 6: Mutations — toggle/del/move/archive/reload via `state.io`

**Files:**
- Modify: `lib/todotxt/tui.ex` (handlers update)
- Modify: `lib/todotxt/tui/state.ex` (`mutate/3` helper, `status/2`, `reloaded/3`)
- Test: `test/todotxt/tui_test.exs` (ajouts — `io` fake qui enregistre les writes)

**Interfaces:**
- Produces : `State.mutate(state, {:op, args}) :: {%State{}, [toast]}` — appelle Ops + `state.io.write/append`, met à jour `mtimes`, clamp sélection ; `io` injecté : `%{read:, write:, append:, stat:}`

- [ ] **Step 1: Tests mutations**

```elixir
test "x on open task completes it and writes via io" do
  test_pid = self()
  io = %{fake_io() | write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end,
                   append: fn _, _ -> :ok end}
  s = state([t("a", 1)], io: io)
  {s2, []} = Tui.update(:toggle_done, s)
  assert hd(s2.tasks).done
  assert_received {:write, "t", [%{done: true}]}
end

test "x on done task reopens; recur spawns next occurrence in the write" do
  test_pid = self()
  io = %{fake_io() | write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end}
  s = state([t("x 2026-09-20 a", 1)], io: io)
  {s2, _} = Tui.update(:toggle_done, s)
  refute hd(s2.tasks).done

  s = state([t("r recur:+1d due:2026-09-22", 1)], io: io)
  {_s2, _} = Tui.update(:toggle_done, s)
  assert_received {:write, "t", ts}
  assert List.last(ts).tags["due"] == "2026-09-23"
  assert List.last(ts).done == false
end

test "x with malformed recur toasts error, no write" do
  test_pid = self()
  io = %{fake_io() | write: fn _, _ -> send(test_pid, :wrote) && :ok end}
  s = state([t("r recur:bad", 1)], io: io)
  {s2, _} = Tui.update(:toggle_done, s)
  refute hd(s2.tasks).done
  assert s2.status =~ "invalid recur"
  refute_received :wrote
end

test "d opens confirm modal; m moves between files" do
  s = state([t("a", 1)])
  {s2, []} = Tui.update({:open_modal, :del}, s)
  assert s2.mode == :input and s2.modal.action == :del

  test_pid = self()
  io = %{fake_io() |
    append: fn p, ts -> send(test_pid, {:append, p}) && :ok end,
    write: fn p, ts -> send(test_pid, {:write, p, ts}) && :ok end}
  s = state([t("a", 1)], io: io)
  {s2, []} = Tui.update(:move, s)
  assert s2.tasks == []
  assert_received {:append, "d"}
  assert_received {:write, "t", []}
end

test "selection stays clamped after delete of last row" do
  s = state([t("a", 1), t("b", 2)], list_idx: 1)
  {s2, []} = Tui.update({:open_modal, :del}, s)
  {s3, []} = Tui.update({:dialog_result, :yes}, s2)
  assert s3.list_idx == 0 and length(s3.tasks) == 1
end
```

- [ ] **Step 2: Vérifier échec** — tests rouges

- [ ] **Step 3: `State.mutate/2` + handlers update**

Dans `state.ex` (`mtime/2` et `refresh_mtimes/1` existent déjà depuis T4) :

```elixir
@doc "Apply an Op result: write files via io, refresh mtimes, clamp, status."
def mutate(s, {:ok, tasks2}, toast) do
  :ok = s.io.write.(s.paths.todo, tasks2)
  %{s | tasks: tasks2, status: toast} |> refresh_mtimes() |> clamp_selection()
end

def mutate(s, {:error, msg}, _toast), do: %{s | status: "error: " <> msg}
```

Dans `tui.ex` :

```elixir
def update(:toggle_done, s) do
  case State.selected_task(s) do
    nil -> {s, []}
    %{done: true} = t -> {State.mutate(s, Ops.uncomplete(s.tasks, t), "#{t.line}: reopened"), []}
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
      {%{s | done_tasks: done2, status: "#{t.line}: moved to todo"} |> State.clamp_selection(), []}

    _ -> {s, []}
  end
end

def update(:reload, s), do: {reload(s), []}

defp reload(s) do
  with {:ok, tasks} <- s.io.read.(s.paths.todo),
       {:ok, done} <- s.io.read.(s.paths.done) do
    %{s | tasks: tasks, done_tasks: done} |> State.refresh_mtimes() |> State.clamp_selection()
  else
    {:error, m} -> %{s | status: "error: " <> m}
  end
end
```

Note implémentation : après `Ops.complete` avec recur, on append puis `reload` — la source de vérité reste le fichier (évite le drift mémoire/fichier).

- [ ] **Step 4: Vérifier** — `mix test test/todotxt/tui_test.exs` → vert

- [ ] **Step 5: Commit** — `git commit -m "feat(tui): mutations do/undo/del/move + reload via io injecté"`

---

### Task 7: Modales — TextInput / PickList / AlertDialog

**Files:**
- Modify: `lib/todotxt/tui.ex` (open_modal, modal_event, modal_submit, handle_info résultats)
- Create: `lib/todotxt/tui/modal.ex` (construction des widgets par action)
- Test: `test/todotxt/tui_test.exs` (ajouts)

**Interfaces:**
- Produces : `Modal.open(action, state) :: %{action:, widget:, widget_mod:}` ; conventions `state.modal = %{action: :add|:edit|:append|:prepend|:filter|:del|:archive|:pri|:help, widget: _, widget_mod: Mod}`

**API widgets (vérifiées dans term_ui 1.0) :**
- `TermUI.Widgets.TextInput` — `.new(value:, placeholder:, width:)`, `.init(props) :: {:ok, w}`, `.handle_event(ev, w) :: {:ok, w}`, `.get_value(w)`, `.set_focused(w, true)`
- `TermUI.Widget.PickList` (singulier) — `.init(%{items:, title:, on_select:, on_cancel:})`, `.handle_event :: {:ok, w} | {:ok, w, [{:send, pid, msg}]}` — Enter → `{:send, self(), {:select, item}}`, Esc → `{:send, self(), :cancel}`
- `TermUI.Widgets.AlertDialog` — `.new(type: :confirm, title:, message:, on_result: fn r -> send(self(), {:dialog_result, r}) end)`, `.init`, `.handle_event`, `.show(w)`

- [ ] **Step 1: Tests modales**

```elixir
test "a opens add modal; typing routes to TextInput; Enter submits" do
  test_pid = self()
  io = %{fake_io() | append: fn p, ts -> send(test_pid, {:append, p, ts}) && :ok end}
  s = state([t("x", 1)], io: io)

  {s2, []} = Tui.update({:open_modal, :add}, s)
  assert s2.mode == :input and s2.modal.action == :add

  {:msg, {:modal_event, ev}} = Tui.event_to_msg(Event.key("h"), s2)
  {s3, []} = Tui.update({:modal_event, ev}, s2)
  {:msg, {:modal_event, ev}} = Tui.event_to_msg(Event.key("i"), s3)
  {s4, []} = Tui.update({:modal_event, ev}, s3)
  assert TextInput.get_value(s4.modal.widget) == "hi"

  {s5, []} = Tui.update(:modal_submit, s4)
  assert s5.mode == :normal and s5.modal == nil
  assert_received {:append, "t", [%{description: "hi", line: 2}]}
end

test "Esc cancels modal without mutating" do
  s = state([t("a", 1)], mode: :input, modal: nil)
  {s2, []} = Tui.update({:open_modal, :edit}, s)
  {s3, []} = Tui.update(:modal_cancel, s2)
  assert s3.mode == :normal and s3.modal == nil
end

test "p opens PickList; {:select, item} sets priority" do
  s = state([t("a", 1)])
  {s2, []} = Tui.update({:open_modal, :pri}, s)
  assert s2.modal.action == :pri
  {s3, []} = Tui.update({:select, "B"}, s2)
  assert hd(s3.tasks).priority == ?B
end

test "dialog_result :yes deletes; :no closes" do
  s = state([t("a", 1)])
  {s2, []} = Tui.update({:open_modal, :del}, s)
  {s3, []} = Tui.update({:dialog_result, :no}, s2)
  assert s3.mode == :normal and length(s3.tasks) == 1
  {s4, []} = Tui.update({:open_modal, :del}, s3)
  {s5, []} = Tui.update({:dialog_result, :yes}, s4)
  assert s5.tasks == []
end

test "submit on a task removed by an external reload fails cleanly (review focus 1)" do
  s = state([t("a", 1)])
  {s2, []} = Tui.update({:open_modal, :edit}, s)
  # Simule un reload externe : la ligne 1 n'existe plus.
  s3 = %{s2 | tasks: [Parser.parse("other", 7)], list_idx: 0}
  {s4, []} = Tui.update(:modal_submit, s3)
  assert s4.status =~ "error"
  assert Enum.map(s4.tasks, & &1.line) == [7]
end
```

- [ ] **Step 2: Vérifier échec**

- [ ] **Step 3: `lib/todotxt/tui/modal.ex`**

```elixir
defmodule TodoTxt.Tui.Modal do
  @moduledoc "Builds modal widget state per action."
  alias TodoTxt.Tui.State
  alias TermUI.Widgets.{AlertDialog, TextInput}
  alias TermUI.Widget.PickList

  def open(:add, _s), do: text_modal(:add, "", "New task: ")
  def open(:filter, s), do: text_modal(:filter, Enum.join(s.filter_terms, " "), "Filter: ")

  def open(:edit, s), do: s |> text_modal(:edit, selected_raw(s), "Edit: ") |> with_line(s)
  def open(:append, s), do: s |> text_modal(:append, "", "Append: ") |> with_line(s)
  def open(:prepend, s), do: s |> text_modal(:prepend, "", "Prepend: ") |> with_line(s)

  def open(:pri, s) do
    items = Enum.map(?A..?Z, &<<&1>>) ++ ["(aucune)"]
    {:ok, w} = PickList.init(%{items: items, title: "Priorité", width: 20, height: 12})
    %{action: :pri, widget: w, widget_mod: PickList, line: selected_line(s)}
  end

  def open(:del, s) do
    s |> confirm(:del, "Supprimer", "Supprimer la tâche #{selected_line(s)} ?") |> Map.put(:line, selected_line(s))
  end

  def open(:archive, s), do: confirm(:archive, "Archiver", "Archiver #{s |> State.counts() |> Map.get(:done)} tâche(s) faite(s) ?")

  def open(:help, _s) do
    props = AlertDialog.new(
      type: :info, title: "Aide",
      message: "j/k nav · Tab focus · Enter applique · x/space do-undo · a add · e edit · A/P append/prepend · p prio · d del · m move · R archive · / filter · E $EDITOR · r reload · Esc annule · q quit",
      on_result: fn r -> send(self(), {:dialog_result, r}) end
    )
    {:ok, w} = AlertDialog.init(props)
    %{action: :help, widget: AlertDialog.show(w), widget_mod: AlertDialog}
  end

  defp selected_raw(s), do: (State.selected_task(s) && State.selected_task(s).raw) || ""
  defp selected_line(s), do: State.selected_task(s) && State.selected_task(s).line

  defp text_modal(action, value, prompt) do
    {:ok, w} = TextInput.init(TextInput.new(value: value, placeholder: prompt, width: 60))
    %{action: action, widget: TextInput.set_focused(w, true), widget_mod: TextInput, prompt: prompt}
  end

  defp with_line(modal, s), do: Map.put(modal, :line, selected_line(s))

  defp confirm(action, title, message) do
    props = AlertDialog.new(
      type: :confirm, title: title, message: message,
      on_result: fn r -> send(self(), {:dialog_result, r}) end
    )
    {:ok, w} = AlertDialog.init(props)
    %{action: action, widget: AlertDialog.show(w), widget_mod: AlertDialog}
  end
end
```

- [ ] **Step 4: `tui.ex` — handlers modaux**

```elixir
def update({:open_modal, action}, s) do
  needs_task = action in [:edit, :append, :prepend, :del, :pri]
  if needs_task and State.selected_task(s) == nil do
    {s, []}
  else
    {%{s | mode: :input, modal: Modal.open(action, s)}, []}
  end
end

def update({:modal_event, %Event.Key{key: :escape}}, s), do: update(:modal_cancel, s)

def update({:modal_event, %Event.Key{key: :enter}},
      %{modal: %{widget_mod: TextInput}} = s),
  do: update(:modal_submit, s)

def update({:modal_event, ev}, %{modal: %{widget: w, widget_mod: mod}} = s) do
  case mod.handle_event(ev, w) do
    {:ok, w2} -> {%{s | modal: %{s.modal | widget: w2}}, []}
    {:ok, w2, effects} ->
      Enum.each(effects || [], fn {:send, pid, msg} -> send(pid, msg) end)
      {%{s | modal: %{s.modal | widget: w2}}, []}
  end
end

def update(:modal_cancel, s), do: {%{s | mode: :normal, modal: nil}, []}

def update(:modal_submit, %{modal: modal} = s) do
  s = %{s | mode: :normal, modal: nil}
  text = TextInput.get_value(modal.widget) |> String.trim()

  case {modal.action, text} do
    {_, ""} when modal.action != :filter -> {s, []}
    {:add, text} ->
      task = Ops.add(s.tasks, text, s.today)
      :ok = s.io.append.(s.paths.todo, [task])
      s2 = %{s | tasks: s.tasks ++ [task], status: "#{task.line}: added"}
      {s2 |> State.refresh_mtimes() |> State.clamp_selection(), []}

    {:filter, text} ->
      {%{s | filter_terms: String.split(text, ~r/\s+/, trim: true), list_idx: 0}, []}

    {:edit, text} -> {mutate_line(s, modal.line, &Ops.replace_text(&1, &2, text), "edited"), []}
    {:append, text} -> {mutate_line(s, modal.line, &Ops.append_text(&1, &2, text), "appended"), []}
    {:prepend, text} -> {mutate_line(s, modal.line, &Ops.prepend_text(&1, &2, text), "prepended"), []}
    _ -> {s, []}
  end
end

def update({:select, item}, %{modal: %{action: :pri, line: line}} = s) do
  s = %{s | mode: :normal, modal: nil}
  prio = if item == "(aucune)", do: nil, else: :binary.first(item)
  {mutate_line(s, line, &Ops.set_priority(&1, &2, prio), "priority"), []}
end

def update(:cancel, %{modal: %{widget_mod: PickList}} = s), do: update(:modal_cancel, s)

def update({:dialog_result, r}, %{modal: %{action: a} = m} = s) when r in [:yes, :confirm, :ok] do
  s = %{s | mode: :normal, modal: nil}

  case a do
    :del -> {mutate_line(s, m.line, &Ops.delete/2, "deleted"), []}
    :archive ->
      {open, done} = Ops.archive(s.tasks)
      if done != [], do: s.io.append.(s.paths.done, done)
      {State.mutate(s, {:ok, open}, "archived #{length(done)}"), []}

    # :help et autres infos : fermer sans action.
    _ -> {s, []}
  end
end

def update({:dialog_result, _}, s), do: {%{s | mode: :normal, modal: nil}, []}

# PickList/AlertDialog send {msg} to runtime -> root handle_info -> update (déjà câblé T3)
# Re-fetch par line : la tâche a pu disparaître via un reload externe
# pendant que la modale était ouverte (review focus 1).
defp mutate_line(s, nil, _op, _label), do: s

defp mutate_line(s, line, op, label) do
  case Enum.find(s.tasks, &(&1.line == line)) do
    nil -> %{s | status: "error: task #{line} no longer exists"}
    fresh -> State.mutate(s, op.(s.tasks, fresh), "#{line}: #{label}")
  end
end
```

- [ ] **Step 5: Vérifier** — `mix test` → vert ; `mix format`

- [ ] **Step 6: Commit** — `git commit -m "feat(tui): modales add/edit/append/prepend/filter/pri/del/archive"`

---

### Task 8: `Tui.View` — rendu 3 panes + statusline + modales

**Files:**
- Create: `lib/todotxt/tui/view.ex`
- Modify: `lib/todotxt/tui.ex` (`view/1` → `View.render(state)`)
- Test: `test/todotxt/tui/view_test.exs`

**Interfaces:**
- Produces : `View.render(%State{}) :: RenderNode.t()`

- [ ] **Step 1: Tests structurels du render tree**

```elixir
defmodule TodoTxt.Tui.ViewTest do
  use ExUnit.Case, async: true
  alias TodoTxt.{Parser, Tui.State, Tui.View}
  alias TermUI.Component.RenderNode

  defp st(tasks, opts \\ []) do
    State.new(%{paths: %{todo: "t", done: "d", report: "r"}, tasks: tasks,
                done_tasks: [], today: ~D[2026-09-21], caller: self(), io: fake_io()})
    |> struct!(opts)
  end

  defp fake_io, do: %{read: fn _ -> {:ok, []} end, write: fn _, _ -> :ok end,
                      append: fn _, _ -> :ok end, stat: fn _ -> {:error, :enoent} end}
  defp t(raw, line), do: Parser.parse(raw, line)

  # helpers d'inspection du render tree
  defp texts(%RenderNode{children: children}) when is_list(children),
    do: Enum.flat_map(children, fn
      {node, _constraint} -> texts(node)
      %RenderNode{} = node -> texts(node)
      _ -> []
    end)
  defp texts(%RenderNode{type: :text, content: c}), do: [c]
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
```

(Assertions sur `RenderNode` : `type: :stack|:text`, `direction`, `children` — les enfants contraints sont des tuples `{node, Constraint}`.)

- [ ] **Step 2: Vérifier échec**

- [ ] **Step 3: `lib/todotxt/tui/view.ex`**

```elixir
defmodule TodoTxt.Tui.View do
  @moduledoc "Render tree for the 3-pane layout + statusline + modals."

  import TermUI.Component.Helpers
  alias TodoTxt.Tui.State
  alias TodoTxt.Tui.Modal
  alias TermUI.Layout.Constraint
  alias TermUI.Renderer.Style

  @sel Style.new(attrs: [:reverse])
  @dim Style.new(fg: :bright_black)
  @pri %{?A => Style.new(fg: :red, attrs: [:bold]),
         ?B => Style.new(fg: :yellow), ?C => Style.new(fg: :cyan)}

  def render(s) do
    stack(:vertical, [
      {body(s), Constraint.fill()},
      {statusline(s), Constraint.length(1)}
    ])
  end

  defp body(%{mode: :input, modal: %{widget_mod: mod, widget: w}} = s)
       when mod in [TermUI.Widgets.AlertDialog, TermUI.Widget.PickList] do
    mod.render(w, %{width: s.width, height: s.height})
  end

  defp body(s) do
    stack(:horizontal, [
      {sidebar(s), Constraint.length(22)},
      {task_list(s), Constraint.fill()},
      {detail(s), Constraint.percentage(30) |> Constraint.with_min(24)}
    ])
  end

  defp sidebar(s) do
    entries = State.sidebar_entries(s)

    stack(:vertical, Enum.with_index(entries, fn
      {:header, label}, _ -> text(" " <> label, @dim)
      {:all, label}, i -> item(s, i, label <> count_suffix(s))
      {kind, label, term}, i when kind in [:project, :context] ->
        mark = if term in s.filter_terms, do: "●", else: " "
        item(s, i, " #{mark} #{label}")
      {:view, label, _}, i -> item(s, i, "   " <> label)
    end))
  end

  defp item(s, i, label) do
    style = if s.focus == :sidebar and s.sidebar_idx == i, do: @sel, else: nil
    text(label, style)
  end

  defp count_suffix(s) do
    c = State.counts(s)
    " (#{c.open}/#{c.done + c.open})"
  end

  defp task_list(s) do
    rows = State.rows(s)
    # task_idx = index parmi les {:task} seulement (list_idx réfère les tâches)
    stack(:vertical, render_rows(s, rows, 0))
  end

  defp render_rows(_s, [], _ti), do: [text("  (vide)", @dim)]

  defp render_rows(s, rows, ti) do
    {nodes, _ti} =
      Enum.map_reduce(rows, ti, fn
        {:header, label}, ti -> {text(" " <> label, Style.new(attrs: [:bold])), ti}
        {:task, t}, ti ->
          line = "#{t.line}: #{t.raw}"
          style = cond do
            s.focus == :list and s.list_idx == ti -> @sel
            t.done -> @dim
            Map.has_key?(@pri, t.priority) -> @pri[t.priority]
            true -> nil
          end
          {text(" " <> line, style), ti + 1}
      end)

    nodes
  end

  defp detail(s) do
    case State.selected_task(s) do
      nil -> text("  —", @dim)
      t ->
        fields = [
          {"Ligne", "#{t.line}"},
          {"Priorité", t.priority && <<t.priority>>},
          {"Créée", t.creation_date && Date.to_string(t.creation_date)},
          {"Faite", t.completion_date && Date.to_string(t.completion_date)},
          {"Due", t.tags["due"]}, {"Seuil t:", t.tags["t"]}, {"Recur", t.tags["recur"]},
          {"Projets", Enum.join(t.projects, " ")},
          {"Contextes", Enum.join(t.contexts, " ")}
        ]

        stack(:vertical,
          [text(" " <> t.raw, Style.new(attrs: [:bold])), text("")] ++
            for {k, v} <- fields, v not in [nil, ""], do: text("  #{k}: #{v}"))
    end
  end

  defp statusline(%{mode: :input, modal: %{widget_mod: TextInput, widget: w, prompt: p}} = s) do
    stack(:horizontal, [
      text(" " <> p, Style.new(fg: :cyan)),
      TextInput.render(w, %{width: max(s.width - String.length(p) - 2, 10), height: 1})
    ])
  end

  defp statusline(s) do
    filters = if s.filter_terms == [], do: "", else: "  filter: #{Enum.join(s.filter_terms, " ")}"
    status = if s.status, do: "  │ #{s.status}", else: ""
    view = s.view |> Atom.to_string() |> String.upcase()
    text(" #{view}#{filters}#{status}  ·  a:add e:edit x:do d:del p:pri m:move /:filter E:$EDITOR ?:help q:quit", @dim)
  end
end
```

(`Modal.open(:help, s)` est défini en T7 — `AlertDialog` type `:info`.)

- [ ] **Step 4: Vérifier** — `mix test` → vert ; `mix format`

- [ ] **Step 5: Commit** — `git commit -m "feat(tui): rendu 3 panes + statusline + modales"`

---

### Task 9: Watch mtime + `$EDITOR` + intégration

**Files:**
- Modify: `lib/todotxt/tui.ex` (`:tick`, `:edit_external`, mtimes init)
- Test: `test/todotxt/tui_test.exs` (tick via io.stat fake), `test/todotxt/cli_test.exs` (fichier illisible)

**Interfaces:**
- Consumes : `Command.interval(2_000, :tick)` (émis en T3 init), `io.stat`
- Produces : msg `:tick`, `:edit_external`, flag `{:tui_exit, :edit | :quit}` vers `state.caller`

- [ ] **Step 1: Tests**

```elixir
test "tick reloads when mtime changed externally" do
  test_pid = self()
  old = {{2026, 1, 1}, {0, 0, 0}}
  new = {{2026, 1, 2}, {0, 0, 0}}
  io = %{fake_io() |
    stat: fn "t" -> {:ok, %{mtime: new}}; _ -> {:error, :enoent} end,
    read: fn _ -> send(test_pid, :reread) && {:ok, []} end}
  s = state([], io: io)
  s = %{s | mtimes: %{todo: old, done: nil}}
  {s2, []} = Tui.update(:tick, s)
  assert_received :reread
  assert s2.mtimes.todo == new
  assert s2.status =~ "recharg"
end

test "tick is a no-op when mtimes unchanged" do
  m = {{2026, 1, 1}, {0, 0, 0}}
  io = %{fake_io() |
    stat: fn _ -> {:ok, %{mtime: m}} end,
    read: fn _ -> raise "must not read" end}
  s = %{state([], io: io) | mtimes: %{todo: m, done: m}}
  assert {^s, []} = Tui.update(:tick, s)
end

test "E sends {:tui_exit, :edit} to caller then quits" do
  s = state([])
  {_s, cmds} = Tui.update(:edit_external, s)
  assert_received {:tui_exit, :edit}
  assert TermUI.Command.quit() in cmds or :quit in cmds
end
```

Et dans `cli_test.exs` :

```elixir
test "--tui with unreadable file returns error before starting runtime" do
  # A directory path -> File.read returns {:error, :eisdir}.
  # (enoent reads as {:ok, []} by Store design — use a real error case.)
  dir = Path.join(System.tmp_dir!(), "todotxt-tui-test-#{System.unique_integer([:positive])}")
  File.mkdir_p!(dir)

  env = %{paths: %{todo: dir, done: "d", report: "r"},
          today: ~D[2026-09-21],
          runner: fn _ -> raise "must not run" end}
  assert {:error, msg} = TodoTxt.CLI.run(["--tui"], env)
  assert msg =~ "cannot read"
end
```

- [ ] **Step 2: Vérifier échec**

- [ ] **Step 3: Handlers dans `tui.ex`**

```elixir
def update(:tick, s) do
  todo_m = State.mtime(s.io, s.paths.todo)
  done_m = State.mtime(s.io, s.paths.done)

  if todo_m == s.mtimes[:todo] and done_m == s.mtimes[:done] do
    {s, []}
  else
    {reload(%{s | status: "rechargé (fichier modifié)"}), []}
  end
end

def update(:edit_external, s) do
  if s.caller, do: send(s.caller, {:tui_exit, :edit})
  {s, [Command.quit()]}
end
```

Et dans `init` (tui.ex) : `mtimes` seedé depuis `env.mtimes` ou calculé via `State.refresh_mtimes` au premier `:tick`.

- [ ] **Step 4: Vérifier** — `mix test` → vert ; `mix format --check-formatted`

- [ ] **Step 5: Smoke escript**

```bash
mix escript.build && printf 'x 2026-09-20 done one\n(A) open two +proj @ctx due:2026-09-25\n' > /tmp/todo.txt
./todo --tui -f /tmp/todo.txt   # vérif manuelle : panes, j/k, x, a, E
```

- [ ] **Step 6: Commit** — `git commit -m "feat(tui): watch mtime 2s + \$EDITOR quit/edit/relaunch"`

---

### Task 10: Docs + revue finale

**Files:**
- Modify: `README.md`, `docs/GUIDE.md` (section `--tui` : lancement, keybindings, vues, $EDITOR)
- Modify: `lib/todotxt/commands/help.ex` si pas fait en T3

- [ ] **Step 1: README** — table des flags : `--tui` ; section « TUI » courte (lancement, layout, touches principales, watch, `E`).

- [ ] **Step 2: GUIDE.md** — même contenu en français détaillé.

- [ ] **Step 3: Suite complète + format** — `mix test && mix format --check-formatted && mix escript.build`

- [ ] **Step 4: Commit** — `git commit -m "docs: TUI --tui dans README et GUIDE"`

---

## Self-review notes

- Spec §5 `R`=archive, `E`=$EDITOR : couverts T7/T9. Sidebar `Toutes` reset filtres : T4. Statusline filtres/compteurs : T8.
- Déviations assumées vs spec :
  - Écritures synchrones dans `update` via `state.io` injecté (fichiers petits ; supprime le besoin de `pending_write` — les mtimes seuls préviennent l'auto-reload). Plus simple, testable sans FS.
  - `status` (string en statusline) tient lieu de `toasts` — le widget Toast peut remplacer plus tard sans changer l'API interne.
  - `Ops.add/3` retourne `%Task{}` (l'appelant append) plutôt que `{:ok, tasks', task}` — `add` ne réécrit pas le fichier.
  - `Ops.move` non créé : move = `Store.append(dest, [t])` + `Ops.delete(src)` — la spec l'indiquait comme signature indicative.
- `Ops.agenda/2` partagé (T1) — utilisé par `Commands.Agenda` (T2) et la vue agenda (T4/T8).
- `PickList` = `TermUI.Widget.PickList` (namespace singulier, vérifié sources) ; résultats via `{:send, self(), msg}` → root `handle_info`. `AlertDialog.on_result` → `send(self(), {:dialog_result, r})` idem.
- Squelette T3 volontairement autonome (pas de référence à `State`, créé en T4) — remplacé en T5.
