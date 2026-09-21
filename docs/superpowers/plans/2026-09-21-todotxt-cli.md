# CLI todo.txt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CLI Elixir/escript de gestion de todos au format todo.txt, parité `todo.sh` + extensions `due:`/`recur:`/`t:`, fichiers XDG, sortie texte/`--json`.

**Architecture:** Couches : `Parser`/`Task` (pur) → `Store` (I/O fichiers) → `Query` (pur) → `Commands.*` (métier) → `CLI` (argv/dispatch). Logique métier sans I/O ; `paths` et `today` injectés pour les tests.

**Tech Stack:** Elixir 1.20 / Erlang 29 (mise), escript, ExUnit, Jason (JSON).

**Spec:** `docs/superpowers/specs/2026-09-21-todotxt-cli-design.md`

## Global Constraints

- Binaire escript `todo`, projet `mix` `todotxt`, app `TodoTxt`
- `System.halt` uniquement dans `CLI.main/1` ; erreurs métier = `{:error, msg}` → stderr exit 1, erreurs d'usage = `{:usage, msg}` → stderr exit 2
- Réécritures de fichiers via `Store.write_atomic/2` (tmp + rename) uniquement
- Les numéros affichés sont les index de ligne du fichier, stables sous filtre
- `mix test` vert avant chaque commit ; `mix format` standard
- Dates : `~D[...]`/`Date`, jamais de strings ad hoc ; `today` toujours injecté (jamais `Date.utc_today()` hors de `CLI.main`)
- Aucun I/O fichier en dehors de `Store` ; aucun `IO.puts` en dehors de `CLI`/`Format`

## Review Focus

Inputs risqués que la spec implique sans test dédié — chacun a son test dans la tâche propriétaire :

1. **Fichier avec CRLF ou sans newline final** → `Parser.parse_all/1` doit gérer les deux (test Task 2).
2. **`x` en premier mot d'une vraie tâche** (`x marks the spot`) → interprété comme done par la spec — comportement attendu documenté, testé (Task 2).
3. **`recur:` sans `due:`** → base = date de complétion ; `recur:1w` strict sans `due:` → base = complétion aussi (test Task 9).
4. **`todo.txt`/`done.txt` absents** → lus comme listes vides ; `archive` crée `done.txt` (tests Tasks 4 et 12).
5. **`del`/`do` sur un numéro de ligne qui pointe une ligne vide ou hors bornes** → `{:error, ...}` propre, pas de crash (test Task 8).

---

### Task 1: Scaffold projet mix + escript

**Files:**
- Create: `mix.exs`, `.gitignore`, `README.md`, `lib/todotxt.ex`, `lib/todotxt/cli.ex` (stub), `test/test_helper.exs`
- Test: `test/todotxt_test.exs` (smoke)

**Interfaces:**
- Produces: `TodoTxt.CLI.main/1 :: no_return()` ; binaire `./todo` via `mix escript.build` ; `mix test` fonctionnel.

- [ ] **Step 1: Créer le projet**

```bash
cd /d/sandboxes-publiques/devin-personnel/todotxt
mix new . --app todotxt --module TodoTxt
```

Puis éditer `mix.exs` :

```elixir
def project do
  [
    app: :todotxt,
    version: "0.1.0",
    elixir: "~> 1.18",
    escript: [main_module: TodoTxt.CLI, name: "todo"],
    deps: deps()
  ]
end

defp deps do
  [{:jason, "~> 1.4"}]
end
```

`.gitignore` : ajouter `/todo` (le binaire) aux lignes générées. `cli.ex` stub :

```elixir
defmodule TodoTxt.CLI do
  def main(_argv), do: IO.puts("todo 0.1.0")
end
```

- [ ] **Step 2: Smoke test**

`test/todotxt_test.exs` :

```elixir
defmodule TodoTxtTest do
  use ExUnit.Case
  test "cli module exists" do
    assert function_exported?(TodoTxt.CLI, :main, 1)
  end
end
```

- [ ] **Step 3: Vérifier**

```bash
mix deps.get && mix test && mix escript.build && ./todo
```

Expected: test PASS, `./todo` imprime `todo 0.1.0`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Scaffold projet mix + escript"
```

---

### Task 2: `%Task{}` + `Parser.parse/2` (golden tests spec)

**Files:**
- Create: `lib/todotxt/task.ex`, `lib/todotxt/parser.ex`
- Test: `test/todotxt/parser_test.exs`

**Interfaces:**
- Produces:
  - `%TodoTxt.Task{line, raw, done, completion_date, priority, creation_date, description, projects, contexts, tags}`
  - `TodoTxt.Parser.parse(line :: String.t(), line_no :: pos_integer) :: Task.t()`
  - `TodoTxt.Parser.parse_all(content :: String.t()) :: [Task.t()]`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TodoTxt.ParserTest do
  use ExUnit.Case
  alias TodoTxt.Parser

  test "simple task" do
    t = Parser.parse("call mom", 1)
    assert t.line == 1 and t.description == "call mom"
    refute t.done
    assert t.priority == nil
  end

  test "priority + creation date" do
    t = Parser.parse("(A) 2026-09-20 call mom +family @phone due:2026-09-25", 2)
    assert t.priority == ?A
    assert t.creation_date == ~D[2026-09-20]
    assert t.projects == ["+family"]
    assert t.contexts == ["@phone"]
    assert t.tags == %{"due" => "2026-09-25"}
  end

  test "done task with completion and creation dates" do
    t = Parser.parse("x 2026-09-21 2026-09-20 call mom +family", 3)
    assert t.done and t.completion_date == ~D[2026-09-21]
    assert t.creation_date == ~D[2026-09-20]
    assert t.priority == nil
  end

  test "x alone marks done; x as a word still marks done per spec" do
    assert Parser.parse("x marks the spot", 1).done
  end

  test "(A) not at head stays literal" do
    t = Parser.parse("call mom (A)", 1)
    assert t.priority == nil
    assert t.description =~ "(A)"
  end

  test "urls are not tags" do
    t = Parser.parse("read http://example.com docs", 1)
    assert t.tags == %{}
  end

  test "parse_all: CRLF, no trailing newline, blank lines keep real line numbers" do
    t = Parser.parse_all("first\r\n\r\nsecond")
    assert Enum.map(t, & &1.line) == [1, 3]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

`mix test test/todotxt/parser_test.exs` → FAIL (module undefined).

- [ ] **Step 3: Implement**

`task.ex` :

```elixir
defmodule TodoTxt.Task do
  @enforce_keys [:line]
  defstruct line: nil, raw: "", done: false, completion_date: nil,
            priority: nil, creation_date: nil, description: "",
            projects: [], contexts: [], tags: %{}
  @type t :: %__MODULE__{}
end
```

`parser.ex` :

```elixir
defmodule TodoTxt.Parser do
  alias TodoTxt.Task

  @tag_re ~r/^([A-Za-z][A-Za-z0-9_-]*):(\S+)$/

  def parse(line, line_no) do
    raw = String.trim_trailing(line) |> String.trim_trailing("\r")
    tokens = String.split(raw, ~r/\s+/, trim: true)

    {done, tokens} =
      case tokens do
        ["x" | rest] -> {true, rest}
        _ -> {false, tokens}
      end

    {completion_date, tokens} = if done, do: take_date(tokens), else: {nil, tokens}

    {priority, tokens} =
      case {done, tokens} do
        {false, [<<"(", p, ")">> | rest]} when p in ?A..?Z -> {p, rest}
        _ -> {nil, tokens}
      end

    {creation_date, tokens} = take_date(tokens)

    %Task{
      line: line_no, raw: raw, done: done,
      completion_date: completion_date, priority: priority,
      creation_date: creation_date,
      description: Enum.join(tokens, " "),
      projects: for(<<"+", _::binary>> = t <- tokens, String.length(t) > 1, do: t),
      contexts: for(<<"@", _::binary>> = t <- tokens, String.length(t) > 1, do: t),
      tags: extract_tags(tokens)
    }
  end

  def parse_all(content) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {l, _} -> String.trim(l) == "" end)
    |> Enum.map(fn {l, i} -> parse(l, i) end)
  end

  defp take_date([tok | rest]) do
    case Date.from_iso8601(tok) do
      {:ok, d} -> {d, rest}
      _ -> {nil, [tok | rest]}
    end
  end

  defp take_date([]), do: {nil, []}

  defp extract_tags(tokens) do
    for t <- tokens,
        [_, k, v] <- [Regex.run(@tag_re, t)],
        not String.contains?(v, "://"),
        into: %{},
        do: {k, v}
  end
end
```

- [ ] **Step 4: Run test** → `mix test` PASS.

- [ ] **Step 5: Commit** — `git commit -m "Task struct + parser (spec todo.txt)"`.

---

### Task 3: `Parser.render/1` + helpers métier `Task`

**Files:**
- Modify: `lib/todotxt/parser.ex`, `lib/todotxt/task.ex`
- Test: `test/todotxt/task_test.exs`

**Interfaces:**
- Produces:
  - `Parser.render(Task.t()) :: String.t()`
  - `Task.complete(t, Date.t())`, `Task.uncomplete(t)`, `Task.set_priority(t, char|nil)`, `Task.set_text(t, String.t())`, `Task.append_text(t, s)`, `Task.prepend_text(t, s)` — tous `:: Task.t()`

- [ ] **Step 1: Failing test**

```elixir
test "render round-trips a parsed line" do
  for line <- ["(A) 2026-09-20 call mom +f @p due:2026-09-25",
               "x 2026-09-21 2026-09-20 done thing",
               "plain task"] do
    assert Parser.render(Parser.parse(line, 1)) == line
  end
end

test "complete drops priority and sets completion date" do
  t = Parser.parse("(B) 2026-09-20 call mom", 1) |> Task.complete(~D[2026-09-21])
  assert Parser.render(t) == "x 2026-09-21 2026-09-20 call mom"
end

test "uncomplete strips x and completion date" do
  t = Parser.parse("x 2026-09-21 call mom", 1) |> Task.uncomplete()
  assert Parser.render(t) == "call mom"
end

test "set_priority and append/prepend" do
  t = Parser.parse("call mom", 1)
  assert t |> Task.set_priority(?C) |> Parser.render() == "(C) call mom"
  assert t |> Task.append_text("+fam") |> Parser.render() == "call mom +fam"
  assert t |> Task.prepend_text("please") |> Parser.render() == "please call mom"
end
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`parser.ex`, ajouter :

```elixir
def render(%Task{} = t) do
  [
    if(t.done, do: "x"),
    if(t.done && t.completion_date, do: Date.to_string(t.completion_date)),
    if(!t.done && t.priority, do: <<"(", t.priority, ")">>),
    if(t.creation_date, do: Date.to_string(t.creation_date)),
    t.description
  ]
  |> Enum.reject(&(&1 in [nil, ""]))
  |> Enum.join(" ")
end
```

`task.ex`, ajouter :

```elixir
alias TodoTxt.Parser

def complete(%Task{} = t, today) do
  reparse(%{t | done: true, completion_date: today, priority: nil})
end

def uncomplete(%Task{} = t), do: reparse(%{t | done: false, completion_date: nil})
def set_priority(%Task{} = t, p) when p in ?A..?Z, do: reparse(%{t | priority: p})
def set_priority(%Task{} = t, nil), do: reparse(%{t | priority: nil})
def set_text(%Task{} = t, s), do: reparse(%{t | description: s})
def append_text(%Task{} = t, s), do: set_text(t, String.trim(t.description <> " " <> s))
def prepend_text(%Task{} = t, s), do: set_text(t, String.trim(s <> " " <> t.description))

defp reparse(%Task{} = t), do: Parser.parse(Parser.render(t), t.line)
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `"Parser.render + Task helpers (complete/undo/priority/text)"`.

---

### Task 4: `Store` (paths, read/write atomique, done/report)

**Files:**
- Create: `lib/todotxt/store.ex`, `lib/todotxt/config.ex`
- Test: `test/todotxt/store_test.exs`, `test/todotxt/config_test.exs`

**Interfaces:**
- Produces:
  - `Config.resolve_paths(cli_opts :: map) :: %{todo: p, done: p, report: p}` (flags > env > XDG)
  - `Config.load_file() :: map` (`$XDG_CONFIG_HOME/todotxt/config`, `KEY=value`)
  - `Store.read(path) :: {:ok, [Task.t()]} | {:error, msg}` (fichier absent → `{:ok, []}`)
  - `Store.write(path, [Task.t()]) :: :ok | {:error, msg}` — render + write_atomic
  - `Store.append(path, [Task.t()]) :: :ok | {:error, msg}` (crée si absent)
  - `Store.write_atomic(path, content) :: :ok | {:error, msg}`

- [ ] **Step 1: Failing test** (`store_test.exs`, `tmp_dir` via `System.tmp_dir!()`)

```elixir
setup do
  dir = Path.join(System.tmp_dir!(), "tt#{System.unique_integer([:positive])}")
  File.mkdir_p!(dir)
  %{dir: dir}
end

test "read missing file returns empty list", %{dir: d} do
  assert Store.read(Path.join(d, "todo.txt")) == {:ok, []}
end

test "write then read round-trips tasks", %{dir: d} do
  p = Path.join(d, "todo.txt")
  tasks = Parser.parse_all("(A) one\ntwo")
  assert :ok = Store.write(p, tasks)
  assert {:ok, [t1, t2]} = Store.read(p)
  assert t1.priority == ?A and t2.line == 2
end

test "append creates file and preserves content", %{dir: d} do
  p = Path.join(d, "done.txt")
  :ok = Store.append(p, Parser.parse_all("x done1"))
  :ok = Store.append(p, Parser.parse_all("x done2"))
  {:ok, ts} = Store.read(p)
  assert length(ts) == 2
end
```

`config_test.exs` : `resolve_paths(%{})` avec `XDG_DATA_HOME` setté → `.../todo/todo.txt` ; flag `file:` gagne sur env `TODOTXT_TODO_FILE` (setter via `System.put_env`, cleanup en `on_exit`).

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

```elixir
defmodule TodoTxt.Store do
  alias TodoTxt.Parser

  def read(path) do
    case File.read(path) do
      {:ok, c} -> {:ok, Parser.parse_all(c)}
      {:error, :enoent} -> {:ok, []}
      {:error, r} -> {:error, "cannot read #{path}: #{:file.format_error(r)}"}
    end
  end

  def write(path, tasks) do
    content = Enum.map_join(tasks, "\n", &Parser.render/1)
    write_atomic(path, if(content == "", do: "", else: content <> "\n"))
  end

  def append(path, tasks) do
    File.mkdir_p!(Path.dirname(path))
    content = Enum.map_join(tasks, "\n", &Parser.render/1) <> "\n"
    File.open(path, [:append], &IO.binwrite(&1, content))
  end

  def write_atomic(path, content) do
    File.mkdir_p!(Path.dirname(path))
    tmp = path <> ".tmp"

    with :ok <- File.write(tmp, content),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, r} -> {:error, "cannot write #{path}: #{:file.format_error(r)}"}
    end
  end
end
```

```elixir
defmodule TodoTxt.Config do
  def resolve_paths(opts \\ %{}) do
    data = System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share")
    dir = System.get_env("TODOTXT_DIR") || config_file()["TODO_DIR"] || Path.join(data, "todo")

    %{
      todo: opts[:file] || System.get_env("TODOTXT_TODO_FILE") || Path.join(dir, "todo.txt"),
      done: opts[:done_file] || System.get_env("TODOTXT_DONE_FILE") || Path.join(dir, "done.txt"),
      report: Path.join(dir, "report.txt")
    }
  end

  def config_file do
    cfg = System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")
    path = Path.join(cfg, "todotxt/config")

    case File.read(path) do
      {:ok, c} ->
        for l <- String.split(c, "\n"), [k, v] = String.split(l, "=", parts: 2),
            k != "", into: %{},
            do: {String.trim(k), String.trim(v)}

      _ -> %{}
    end
  end
end
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `"Store + Config (paths XDG/env/flags, I/O atomique)"`.

---

### Task 5: `CLI` skeleton + `add` end-to-end

**Files:**
- Create: `lib/todotxt/commands/add.ex`
- Modify: `lib/todotxt/cli.ex`
- Test: `test/todotxt/cli_test.exs`

**Interfaces:**
- Consumes: `Store.read/write`, `Config.resolve_paths`, `Parser`
- Produces:
  - `CLI.run(argv :: [String.t()], env :: %{paths: map, today: Date.t()}) :: {:ok, String.t() | nil} | {:error, String.t()} | {:usage, String.t()}`
  - `CLI.main/1` : résout env réel (paths Config + `Date.utc_today()`), imprime, halt
  - Contrat commandes : `Mod.run(args :: [String.t()], ctx :: %{paths:, tasks:, today:, opts: map}) :: {:ok, msg} | {:error, msg} | {:usage, msg}` ; les commandes mutantes écrivent via `Store` et retournent `{:ok, "..."}`
  - `opts` : `%{plain: bool, json: bool}`

- [ ] **Step 1: Failing test**

```elixir
defmodule TodoTxt.CLITest do
  use ExUnit.Case

  setup do
    dir = Path.join(System.tmp_dir!(), "tt#{System.unique_integer([:positive])}")
    env = %{
      paths: %{todo: Path.join(dir, "todo.txt"), done: Path.join(dir, "done.txt"),
               report: Path.join(dir, "report.txt")},
      today: ~D[2026-09-21]
    }
    %{env: env, dir: dir}
  end

  test "add appends with creation date and echoes line", %{env: e} do
    assert {:ok, out} = TodoTxt.CLI.run(["add", "call", "mom", "+fam"], e)
    assert out =~ "1:"
    {:ok, [t]} = TodoTxt.Store.read(e.paths.todo)
    assert t.creation_date == ~D[2026-09-21]
    assert t.projects == ["+fam"]
  end

  test "add without args is a usage error", %{env: e} do
    assert {:usage, _} = TodoTxt.CLI.run(["add"], e)
  end

  test "unknown command is a usage error", %{env: e} do
    assert {:usage, m} = TodoTxt.CLI.run(["bogus"], e)
    assert m =~ "bogus"
  end
end
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`cli.ex` :

```elixir
defmodule TodoTxt.CLI do
  alias TodoTxt.{Config, Store}

  @commands %{"add" => TodoTxt.Commands.Add, "a" => TodoTxt.Commands.Add}

  def main(argv) do
    env = %{paths: Config.resolve_paths(), today: Date.utc_today()}

    case run(argv, env) do
      {:ok, out} -> if(out, do: IO.puts(out)); System.halt(0)
      {:error, m} -> IO.puts(:stderr, "todo: " <> m); System.halt(1)
      {:usage, m} -> IO.puts(:stderr, "usage: " <> m); System.halt(2)
    end
  end

  def run(argv, env) do
    {opts, rest} = parse_global(argv, %{file: nil, done_file: nil, plain: false, json: false})
    env = put_in(env.paths, Config.resolve_paths(opts)) |> Map.put(:opts, opts)

    case rest do
      [cmd | args] ->
        case @commands[cmd] do
          nil -> {:usage, "unknown command #{cmd} (try: todo help)"}
          mod ->
            with {:ok, tasks} <- Store.read(env.paths.todo),
                 {:ok, done} <- Store.read(env.paths.done) do
              mod.run(args, Map.merge(env, %{tasks: tasks, done_tasks: done}))
            end
        end

      [] -> {:usage, "no command (try: todo help)"}
    end
  end

  defp parse_global(argv, opts) do
    case argv do
      ["-f", v | r] -> parse_global(r, %{opts | file: v})
      ["--file", v | r] -> parse_global(r, %{opts | file: v})
      ["-d", v | r] -> parse_global(r, %{opts | done_file: v})
      ["--done-file", v | r] -> parse_global(r, %{opts | done_file: v})
      ["--plain" | r] -> parse_global(r, %{opts | plain: true})
      ["--json" | r] -> parse_global(r, %{opts | json: true})
      _ -> {opts, argv}
    end
  end
end
```

`commands/add.ex` :

```elixir
defmodule TodoTxt.Commands.Add do
  alias TodoTxt.{Parser, Store}

  def run([], _), do: {:usage, "todo add \"TASK\""}

  def run(words, %{paths: paths, tasks: tasks, today: today}) do
    line = (tasks |> Enum.map(& &1.line) |> Enum.max(fn -> 0 end)) + 1
    task = Parser.parse(Enum.join([Date.to_string(today) | words], " "), line)

    case Store.append(paths.todo, [task]) do
      :ok -> {:ok, "#{line}: #{Parser.render(task)}"}
      {:error, m} -> {:error, m}
    end
  end
end
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `"CLI skeleton + commande add"`.

---

### Task 6: `Query` + `Format` + `ls`/`list`

**Files:**
- Create: `lib/todotxt/query.ex`, `lib/todotxt/format.ex`, `lib/todotxt/commands/list.ex`
- Modify: `lib/todotxt/cli.ex` (register `ls`, `list`)
- Test: `test/todotxt/query_test.exs`, `test/todotxt/format_test.exs`, `cli_test.exs` (ajouts)

**Interfaces:**
- Produces:
  - `Query.filter([Task.t()], terms :: [String.t()]) :: [Task.t()]` — AND, `+p`/`@c` exact token, sinon substring
  - `Query.sort([Task.t()]) :: [Task.t()]` — priority asc (nil dernier), puis `line`
  - `Query.visible([Task.t()], Date.t()) :: [Task.t()]` — exclut non-done avec `t:` futur
  - `Format.tasks([Task.t()], opts) :: String.t()` — `"N: <ligne>"`, couleurs sauf `plain`/`NO_COLOR`
  - `Format.task_map(Task.t()) :: map` (pour JSON, Task 13)

- [ ] **Step 1: Failing tests**

```elixir
# query_test
test "sort: priority then line, no-priority last" do
  ts = Parser.parse_all("plain\n(B) b\n(A) a")
  assert Enum.map(Query.sort(ts), & &1.line) == [3, 2, 1]
end

test "filter: terms AND, +p exact, substring" do
  ts = Parser.parse_all("call mom +fam\ncall dad\nx done +fam")
  assert Enum.map(Query.filter(ts, ["+fam"]), & &1.line) == [1, 3]
  assert Enum.map(Query.filter(ts, ["mom"]), & &1.line) == [1]
  assert Query.filter(ts, ["dad", "+fam"]) == []
end

test "visible hides future t: threshold, shows reached" do
  ts = Parser.parse_all("later t:2026-10-01\nnow t:2026-09-01\nplain\nx done t:2099-01-01")
  assert Enum.map(Query.visible(ts, ~D[2026-09-21]), & &1.line) == [2, 3, 4]
end
```

```elixir
# cli_test ajouts
test "ls lists sorted with stable line numbers", %{env: e} do
  File.write!(e.paths.todo, "plain\n(B) b\n(A) a t:2099-01-01\n")
  # note: t:2099 hidden -> only lines 1,2 shown; (B) before plain
  assert {:ok, out} = TodoTxt.CLI.run(["--plain", "ls"], e)
  assert out == "2: (B) b\n1: plain"
end
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`query.ex` :

```elixir
defmodule TodoTxt.Query do
  def filter(tasks, terms) do
    Enum.filter(tasks, fn t -> Enum.all?(terms, &match?(&1, t)) end)
  end

  defp match?(<<"+"::binary, _::binary>> = term, t), do: term in t.projects
  defp match?(<<"@"::binary, _::binary>> = term, t), do: term in t.contexts
  defp match?(term, t), do: String.contains?(String.downcase(t.raw), String.downcase(term))

  def sort(tasks), do: Enum.sort_by(tasks, &{&1.priority || 256, &1.line})

  def visible(tasks, today) do
    Enum.filter(tasks, fn t ->
      t.done || case t.tags["t"] do
        nil -> true
        v -> case Date.from_iso8601(v) do
          {:ok, d} -> Date.compare(d, today) != :gt
          _ -> true
        end
      end
    end)
  end
end
```

`format.ex` :

```elixir
defmodule TodoTxt.Format do
  @colors %{?A => IO.ANSI.red() <> IO.ANSI.bright(), ?B => IO.ANSI.yellow(),
            ?C => IO.ANSI.cyan()}

  def tasks(tasks, opts) do
    color = not opts.plain and is_nil(System.get_env("NO_COLOR")) and
              System.get_env("TERM") not in [nil, "dumb"]

    Enum.map_join(tasks, "\n", fn t ->
      line = "#{t.line}: #{t.raw}"
      if color, do: colorize(t, line), else: line
    end)
  end

  defp colorize(%{done: true}, line), do: IO.ANSI.faint() <> line <> IO.ANSI.reset()
  defp colorize(%{priority: p}, line) when p in [?A, ?B, ?C],
    do: @colors[p] <> line <> IO.ANSI.reset()
  defp colorize(_, line), do: line

  def task_map(t) do
    %{line: t.line, done: t.done, priority: if(t.priority, do: <<t.priority>>),
      completion_date: t.completion_date && Date.to_string(t.completion_date),
      creation_date: t.creation_date && Date.to_string(t.creation_date),
      description: t.description, projects: t.projects, contexts: t.contexts,
      tags: t.tags}
  end
end
```

`commands/list.ex` :

```elixir
defmodule TodoTxt.Commands.List do
  alias TodoTxt.{Format, Query}

  def run(terms, %{tasks: tasks, today: today, opts: opts}) do
    shown = tasks |> Query.visible(today) |> Query.filter(terms) |> Query.sort()
    {:ok, if(opts.json, do: Jason.encode!(Enum.map(shown, &Format.task_map/1), pretty: true),
                         else: Format.tasks(shown, opts))}
  end
end
```

Register : `"ls" => List, "list" => List` dans `@commands`.

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `"Query + Format + ls (tri, filtres, couleurs, seuils t:)"`.

---

### Task 7: `do`, `undo`, `del`/`rm`

**Files:**
- Create: `lib/todotxt/commands/do.ex`, `undo.ex`, `del.ex`, `lib/todotxt/commands/helpers.ex`
- Modify: `cli.ex` (register `do`, `undo`, `del`, `rm`)
- Test: `cli_test.exs`

**Interfaces:**
- Consumes: `Task.complete/uncomplete`, `Store.write`
- Produces: `Helpers.fetch(tasks, n_str) :: {:ok, Task.t()} | {:error, msg}` (parse int + borne, Review Focus #5)

- [ ] **Step 1: Failing tests**

```elixir
test "do marks done with today, drops priority", %{env: e} do
  File.write!(e.paths.todo, "(A) call mom\nother\n")
  assert {:ok, _} = CLI.run(["do", "1"], e)
  assert {:ok, [t1, _]} = Store.read(e.paths.todo)
  assert t1.done and t1.completion_date == ~D[2026-09-21] and t1.priority == nil
end

test "do on bad number and on already-done", %{env: e} do
  File.write!(e.paths.todo, "x 2026-01-01 done\n")
  assert {:error, m} = CLI.run(["do", "9"], e)
  assert m =~ "9"
  assert {:error, _} = CLI.run(["do", "abc"], e)
end

test "undo reopens", %{env: e} do
  File.write!(e.paths.todo, "x 2026-09-21 task\n")
  {:ok, _} = CLI.run(["undo", "1"], e)
  {:ok, [t]} = Store.read(e.paths.todo)
  refute t.done
end

test "del removes line; del N TERM strips term", %{env: e} do
  File.write!(e.paths.todo, "one\ntwo +p\n")
  {:ok, _} = CLI.run(["del", "2", "+p"], e)
  {:ok, [_, t]} = Store.read(e.paths.todo)
  assert t.raw == "two"
  {:ok, _} = CLI.run(["del", "1"], e)
  assert {:ok, [t]} = Store.read(e.paths.todo)
  assert t.raw == "two"
end
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`commands/helpers.ex` :

```elixir
defmodule TodoTxt.Commands.Helpers do
  def fetch(tasks, n) do
    case Integer.parse(n) do
      {i, ""} ->
        case Enum.find(tasks, &(&1.line == i)) do
          nil -> {:error, "no task #{n}"}
          t -> {:ok, t}
        end
      _ -> {:error, "invalid task number #{inspect(n)}"}
    end
  end

  def replace(tasks, new), do: Enum.map(tasks, &if(&1.line == new.line, do: new, else: &1))
end
```

`commands/do.ex` :

```elixir
defmodule TodoTxt.Commands.Do do
  alias TodoTxt.{Commands.Helpers, Store, Task, Parser}

  def run([n | _], %{tasks: tasks, paths: paths, today: today}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         :ok <- Store.write(paths.todo, Helpers.replace(tasks, Task.complete(t, today))) do
      recur_note =
        case Task.next_recurrence(t, today) do
          nil -> ""
          new ->
            new = %{new | line: length(tasks) + 1}
            Store.append(paths.todo, [new])
            "\n#{new.line}: #{Parser.render(new)}"
        end

      {:ok, "#{t.line}: #{Parser.render(Task.complete(t, today))}#{recur_note}"}
    end
  end

  def run(_, _), do: {:usage, "todo do ITEM#"}
end
```

`undo.ex` : même squelette, `Task.uncomplete`. `del.ex` :

```elixir
def run([n], ctx), do: delete(ctx, n, nil)
def run([n, term], ctx), do: delete(ctx, n, term)

defp delete(%{tasks: tasks, paths: paths}, n, nil) do
  with {:ok, t} <- Helpers.fetch(tasks, n) do
    Store.write(paths.todo, Enum.reject(tasks, &(&1.line == t.line)))
    |> then(fn :ok -> {:ok, "#{t.line}: deleted #{t.raw}"}; e -> e end)
  end
end

defp delete(%{tasks: tasks, paths: paths}, n, term) do
  with {:ok, t} <- Helpers.fetch(tasks, n) do
    desc = t.description |> String.split(~r/\s+/) |> Enum.reject(&(&1 == term)) |> Enum.join(" ")
    new = Task.set_text(t, desc)
    with :ok <- Store.write(paths.todo, Helpers.replace(tasks, new)),
         do: {:ok, "#{t.line}: #{Parser.render(new)}"}
  end
end
```

- [ ] **Step 4: Run** → PASS (note : `Task.next_recurrence` n'existe pas encore → pour que `do` compile, ajouter dans `task.ex` un stub `def next_recurrence(_, _), do: nil` — implémenté Task 9). **Step 5: Commit** — `"Commandes do/undo/del"`.

---

### Task 8: `pri`, `depri`, `append`, `prepend`, `replace`

**Files:**
- Create: `commands/pri.ex`, `depri.ex`, `append.ex`, `prepend.ex`, `replace.ex`
- Modify: `cli.ex` (register)
- Test: `cli_test.exs`

**Interfaces:** Consume `Helpers.fetch/replace`, `Task.set_priority/append_text/prepend_text/set_text`. Produce rien de neuf pour les autres tâches.

- [ ] **Step 1: Failing tests**

```elixir
test "pri/depri/append/prepend/replace", %{env: e} do
  File.write!(e.paths.todo, "call mom\n")
  {:ok, _} = CLI.run(["pri", "1", "B"], e)
  {:ok, [t]} = Store.read(e.paths.todo)
  assert t.priority == ?B
  {:ok, _} = CLI.run(["depri", "1"], e)
  {:ok, [t]} = Store.read(e.paths.todo)
  assert t.priority == nil
  {:ok, _} = CLI.run(["append", "1", "+fam"], e)
  {:ok, _} = CLI.run(["prepend", "1", "please"], e)
  {:ok, [t]} = Store.read(e.paths.todo)
  assert t.raw == "please call mom +fam"
  {:ok, _} = CLI.run(["replace", "1", "new", "text", "+p"], e)
  {:ok, [t]} = Store.read(e.paths.todo)
  assert t.raw == "new text +p"
end

test "pri rejects invalid priority and done tasks", %{env: e} do
  File.write!(e.paths.todo, "x done\nopen\n")
  assert {:error, _} = CLI.run(["pri", "2", "1"], e)
  assert {:error, _} = CLI.run(["pri", "1", "A"], e)
end
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement** — squelette commun (fetch → transform → `Store.write(Helpers.replace(tasks, new))` → `{:ok, "N: <render>"}`) :

`pri.ex` :

```elixir
defmodule TodoTxt.Commands.Pri do
  alias TodoTxt.{Commands.Helpers, Parser, Store, Task}

  def run([n, p], %{tasks: tasks, paths: paths}) do
    with {:ok, t} <- Helpers.fetch(tasks, n),
         :ok <- valid_priority(t, p),
         new = Task.set_priority(t, String.first(p) |> :binary.first()),
         :ok <- Store.write(paths.todo, Helpers.replace(tasks, new)) do
      {:ok, "#{t.line}: #{Parser.render(new)}"}
    end
  end

  def run(_, _), do: {:usage, "todo pri ITEM# A-Z"}

  defp valid_priority(t, <<c>>) when c in ?A..?Z do
    if t.done, do: {:error, "task #{t.line} is already done"}, else: :ok
  end

  defp valid_priority(_, p), do: {:error, "invalid priority #{inspect(p)} (A-Z)"}
end
```

`depri.ex` : `run([n])` → fetch → `Task.set_priority(t, nil)` → write → `{:ok, "N: deprioritized"}`.

`append.ex` / `prepend.ex` : `run([n | words])` → fetch → `Task.append_text(t, Enum.join(words, " "))` / `prepend_text` → write → `{:ok, "N: <render>"}`.

`replace.ex` :

```elixir
def run([n | words], %{tasks: tasks, paths: paths}) do
  with {:ok, t} <- Helpers.fetch(tasks, n),
       new = Parser.parse(Enum.join(words, " "), t.line),
       :ok <- Store.write(paths.todo, Helpers.replace(tasks, new)) do
    {:ok, "#{t.line}: #{Parser.render(new)}"}
  end
end
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `"Commandes pri/depri/append/prepend/replace"`.

---

### Task 9: `recur:` — `Task.next_recurrence/2`

**Files:**
- Modify: `lib/todotxt/task.ex` (remplace le stub de Task 7)
- Test: `test/todotxt/task_test.exs`

**Interfaces:**
- Produces: `Task.next_recurrence(%Task{}, today :: Date.t()) :: Task.t() | nil` — task prête à re-parser/appender (`line` à fixer par l'appelant), `due:` recalculé, priorité/projets/contextes/tags conservés, `creation_date` = today.

- [ ] **Step 1: Failing tests**

```elixir
test "recur +1w: next due = completion + 7d" do
  t = Parser.parse("(A) renew +sub due:2026-09-25 recur:+1w", 1)
  n = Task.next_recurrence(t, ~D[2026-09-21])
  assert n.tags["due"] == "2026-09-28"
  assert n.priority == ?A and n.projects == ["+sub"]
  assert n.creation_date == ~D[2026-09-21]
end

test "recur 1w strict: next due = old due + 7d" do
  t = Parser.parse("renew due:2026-09-25 recur:1w", 1)
  n = Task.next_recurrence(t, ~D[2026-09-21])
  assert n.tags["due"] == "2026-10-02"
end

test "recur without due: base = completion date" do
  t = Parser.parse("water plants recur:+3d", 1)
  assert Task.next_recurrence(t, ~D[2026-09-21]).tags["due"] == "2026-09-24"
end

test "no recur tag -> nil; invalid recur -> nil" do
  assert Task.next_recurrence(Parser.parse("x", 1), ~D[2026-09-21]) == nil
  assert Task.next_recurrence(Parser.parse("x recur:banana", 1), ~D[2026-09-21]) == nil
end
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**

```elixir
def next_recurrence(%Task{tags: %{"recur" => r}} = t, today) do
  with {:ok, strict, n, unit} <- parse_recur(r),
       base when not is_nil(base) <- recur_base(t, strict, today) do
    new_due = shift(base, n, unit)
    desc = update_tag(t.description, "due", Date.to_string(new_due))

    raw =
      [if(t.priority, do: <<"(", t.priority, ")">>), Date.to_string(today), desc]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    Parser.parse(raw, 0)
  else
    _ -> nil
  end
end

def next_recurrence(_, _), do: nil

defp parse_recur(r) when is_binary(r) do
  case Regex.run(~r/^(\+?)(\d+)([dwmy])$/, r) do
    [_, plus, n, u] -> {:ok, plus == "", String.to_integer(n), u}
    _ -> :error
  end
end

defp parse_recur(_), do: :error

defp recur_base(t, strict, today) do
  if strict do
    case t.tags["due"] && Date.from_iso8601(t.tags["due"]) do
      {:ok, d} -> d
      _ -> today
    end
  else
    today
  end
end

defp shift(d, n, "d"), do: Date.add(d, n)
defp shift(d, n, "w"), do: Date.add(d, n * 7)
defp shift(d, n, "m"), do: Date.shift(d, month: n)
defp shift(d, n, "y"), do: Date.shift(d, year: n)

defp update_tag(desc, key, value) do
  re = ~r/\b#{key}:\S+/
  if Regex.match?(re, desc),
    do: Regex.replace(re, desc, "#{key}:#{value}"),
    else: desc <> " #{key}:#{value}"
end
```

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `"recur: occurrences (relatif +N / strict N, base due ou complétion)"`.

---

### Task 10: `move`/`mv`, `listall`, `listproj`, `listcon`, `listpri`

**Files:**
- Create: `commands/move.ex`, `listall.ex`, `listmeta.ex` (listproj/listcon/listpri)
- Modify: `cli.ex` (register `move`,`mv`,`listall`,`lsa`,`listproj`,`lsprj`,`listcon`,`lsc`,`listpri`,`lspr`)
- Test: `cli_test.exs`

**Interfaces:** Consume `Helpers`, `Query.sort`, `Format.tasks`, `Store.append`. Produce rien de neuf.

- [ ] **Step 1: Failing tests**

```elixir
test "mv moves task to done.txt", %{env: e} do
  File.write!(e.paths.todo, "one\ntwo\n")
  {:ok, _} = CLI.run(["mv", "1", "done"], e)
  assert {:ok, [t]} = Store.read(e.paths.todo)
  assert t.raw == "two"
  assert {:ok, [d]} = Store.read(e.paths.done)
  assert d.raw == "one"
end

test "listall includes done file; listproj/listcon/listpri", %{env: e} do
  File.write!(e.paths.todo, "a +p1 @c1\nb +p2\n")
  File.write!(e.paths.done, "x 2026-09-20 old +p1\n")
  {:ok, out} = CLI.run(["--plain", "listall"], e)
  assert out =~ "a +p1" and out =~ "old +p1"
  {:ok, out} = CLI.run(["--plain", "listproj"], e)
  assert out =~ "+p1" and out =~ "+p2"
  {:ok, out} = CLI.run(["--plain", "listcon"], e)
  assert out =~ "@c1"
  {:ok, _} = CLI.run(["pri", "1", "A"], e)
  {:ok, out} = CLI.run(["--plain", "listpri", "A"], e)
  assert out =~ "a +p1"
end
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`move.ex` : `run([n, dest])` avec `dest` ∈ `{"done"→paths.done, "todo"→paths.todo}` (sinon usage) ; fetch dans le fichier source, `Store.write` sans la ligne, `Store.append` dans dest, `{:ok, "N: moved to DEST"}`.

`listall.ex` : concat `tasks ++ done_tasks`, `Query.sort`, `Format.tasks` (ou JSON).

`listmeta.ex` — trois fonctions dans un module :

```elixir
defmodule TodoTxt.Commands.ListMeta do
  alias TodoTxt.Format

  def run(["proj" | _], ctx), do: list(ctx, & &1.projects)
  def run(["con" | _], ctx), do: list(ctx, & &1.contexts)

  def run(["pri", p], ctx) do
    with [c] <- String.to_charlist(p), true <- c in ?A..?Z do
      shown = ctx.tasks |> Enum.filter(&(&1.priority == c)) |> TodoTxt.Query.sort()
      {:ok, Format.tasks(shown, ctx.opts)}
    else
      _ -> {:usage, "todo listpri A-Z"}
    end
  end

  def run(_, _), do: {:usage, "todo listproj|listcon|listpri [A-Z]"}

  defp list(%{tasks: t, done_tasks: d, opts: o}, fun) do
    vals = (t ++ d) |> Enum.flat_map(fun) |> Enum.uniq() |> Enum.sort()
    {:ok, Enum.join(vals, "\n")}
  end
end
```

Dispatch `cli.ex` : les entrées `@commands` peuvent être `Mod` ou `{Mod, sub}` ; l'appel devient :

```elixir
case @commands[cmd] do
  nil -> {:usage, "unknown command #{cmd} (try: todo help)"}
  {mod, sub} -> dispatch.(mod, [sub | args])
  mod -> dispatch.(mod, args)
end
```

avec `dispatch` = la fonction qui charge tasks/done via `Store` puis appelle `mod.run(args, ctx)`. Register : `"listproj" => {ListMeta, "proj"}`, `"lsprj" => {ListMeta, "proj"}`, `"listcon" => {ListMeta, "con"}`, `"lsc" => {ListMeta, "con"}`, `"listpri" => {ListMeta, "pri"}`, `"lspr" => {ListMeta, "pri"}`, `"listall" => ListAll`, `"lsa" => ListAll`, `"move" => Move`, `"mv" => Move`.

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `"mv + listall + listproj/listcon/listpri"`.

---

### Task 11: `due` + `agenda`

**Files:**
- Create: `commands/due.ex` (inclut `agenda`), modify `query.ex` (`due_bucket/2`, `with_due/1`)
- Modify: `cli.ex` (register `due`, `agenda`)
- Test: `cli_test.exs`, `query_test.exs`

**Interfaces:**
- Produces: `Query.due_date(Task.t()) :: Date.t() | nil`, `Query.due_bucket(Task.t(), today) :: :overdue|:today|:week|:later|:none`

- [ ] **Step 1: Failing tests**

```elixir
test "due buckets", %{env: e} do
  File.write!(e.paths.todo,
    "old due:2026-09-19\nnow due:2026-09-21\nsoon due:2026-09-25\nfar due:2026-10-15\nx done due:2026-09-19\n")
  {:ok, out} = CLI.run(["--plain", "due"], e)
  [overdue | _] = String.split(out, "\n\n")
  assert overdue =~ "old" and overdue =~ "OVERDUE"
  assert out =~ "TODAY" and out =~ "THIS WEEK" and out =~ "LATER"
  refute out =~ "x done"  # done tasks excluded
end

test "agenda lists next 14 days by date", %{env: e} do
  File.write!(e.paths.todo, "a due:2026-09-22\nb due:2026-09-22\nc t:2026-09-25 due:2026-09-26\n")
  {:ok, out} = CLI.run(["--plain", "agenda"], e)
  assert out =~ "2026-09-22" and out =~ "a due" and out =~ "b due"
end
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

`query.ex` ajouts :

```elixir
def due_date(t) do
  case t.tags["due"] && Date.from_iso8601(t.tags["due"]) do
    {:ok, d} -> d
    _ -> nil
  end
end

def due_bucket(t, today) do
  case due_date(t) do
    nil -> :none
    d ->
      diff = Date.diff(d, today)
      cond do
        diff < 0 -> :overdue
        diff == 0 -> :today
        diff <= 7 -> :week
        true -> :later
      end
  end
end
```

`due.ex` :

```elixir
def run(_, %{tasks: tasks, today: today, opts: opts}) do
  open = Enum.reject(tasks, & &1.done)
  groups = for b <- [:overdue, :today, :week, :later] do
    ts = open |> Enum.filter(&(Query.due_bucket(&1, today) == b)) |> Query.sort()
    if ts == [], do: nil, else: "#{String.upcase(to_string(b)) |> String.replace("WEEK","THIS WEEK")}:\n" <> Format.tasks(ts, opts)
  end
  {:ok, groups |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")}
end
```

`agenda` (même module, dispatch `run(["agenda"|_])` ou module séparé `commands/agenda.ex`) : tâches ouvertes avec `due_date` dans `today..today+14`, groupées par date exacte, `Format.tasks` sous chaque `YYYY-MM-DD:`.

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `"Commandes due + agenda (buckets overdue/today/week/later)"`.

---

### Task 12: `archive`, `dedupe`, `report`, `edit`, `help`, `--version`, `listaddons`

**Files:**
- Create: `commands/archive.ex`, `dedupe.ex`, `report.ex`, `edit.ex`, `help.ex`
- Modify: `cli.ex` (register + gérer `--version` et `-h`/`help` hors dispatch)
- Test: `cli_test.exs`

- [ ] **Step 1: Failing tests**

```elixir
test "archive moves x tasks to done.txt and creates it", %{env: e} do
  File.write!(e.paths.todo, "x done1\nopen\nx done2\n")
  {:ok, _} = CLI.run(["archive"], e)
  assert {:ok, [t]} = Store.read(e.paths.todo)
  assert t.raw == "open"
  {:ok, ds} = Store.read(e.paths.done)
  assert length(ds) == 2
end

test "dedupe removes duplicate lines keeping first", %{env: e} do
  File.write!(e.paths.todo, "same\nother\nsame\n")
  {:ok, _} = CLI.run(["dedupe"], e)
  {:ok, ts} = Store.read(e.paths.todo)
  assert Enum.map(ts, & &1.raw) == ["same", "other"]
end

test "report appends dated stats", %{env: e} do
  File.write!(e.paths.todo, "a\nb\n")
  File.write!(e.paths.done, "x c\n")
  {:ok, _} = CLI.run(["report"], e)
  assert File.read!(e.paths.report) =~ "2026-09-21 2 1"
end

test "help and --version", %{env: e} do
  assert {:ok, out} = CLI.run(["help"], e)
  assert out =~ "add" and out =~ "ls" and out =~ "do"
  assert {:ok, out} = CLI.run(["--version"], e)
  assert out =~ "todo 0.1.0"
end
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

- `archive.ex` : `Store.append(paths.done, done_part)` + `Store.write(paths.todo, open_part)` ; `{:ok, "archived N tasks"}`.
- `dedupe.ex` : `Enum.uniq_by(& &1.raw)` → write ; `{:ok, "removed N duplicates"}`.
- `report.ex` : append ligne `"#{today} #{length(open)} #{length(done)}"` dans `paths.report` — nécessite d'ajouter dans `store.ex` :

```elixir
def append_line(path, line) do
  File.mkdir_p!(Path.dirname(path))
  File.open(path, [:append], &IO.binwrite(&1, line <> "\n"))
end
```
- `edit.ex` : `System.cmd(editor, [paths.todo])` avec `editor = System.get_env("EDITOR") || "vi"`, `into: IO.stream(:stdio, :line)` pour hériter du terminal ; `{:error, ...}` si exit ≠ 0.
- `help.ex` : texte statique listant toutes les commandes.
- `cli.ex` : intercepter `["--version"]`/`["-h"]`/`["help"]` avant dispatch (`--version` → `{:ok, "todo 0.1.0"}`, `-h` → help) ; `listaddons` → `{:ok, "(no addons support)"}`.

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `"archive/dedupe/report/edit/help/version"`.

---

### Task 13: `--json` complet + README + release

**Files:**
- Modify: `commands/listall.ex`, `due.ex`, `agenda`, `listmeta.ex` (sortie JSON), `format.ex` (`tasks_json/1`)
- Modify: `README.md`
- Test: `cli_test.exs`

**Interfaces:**
- Produces: `Format.tasks_json([Task.t()]) :: String.t()` via `Jason.encode!(Enum.map(ts, &task_map/1), pretty: true)`

- [ ] **Step 1: Failing tests**

```elixir
test "ls --json emits decodable task list", %{env: e} do
  File.write!(e.paths.todo, "(A) call mom +fam @p due:2026-09-25\n")
  {:ok, json} = CLI.run(["--json", "ls"], e)
  assert [%{"line" => 1, "priority" => "A", "tags" => %{"due" => "2026-09-25"}}] =
           Jason.decode!(json)
end

test "listall/due --json also emit JSON", %{env: e} do
  File.write!(e.paths.todo, "a due:2026-09-19\n")
  assert {:ok, j} = CLI.run(["--json", "due"], e)
  assert [_ | _] = Jason.decode!(j)
end
```

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement** — ajouter dans `format.ex` :

```elixir
def render(tasks, %{json: true}), do: tasks_json(tasks)
def render(tasks, opts), do: tasks(tasks, opts)

def tasks_json(tasks), do: Jason.encode!(Enum.map(tasks, &task_map/1), pretty: true)
```

Dans chaque commande listante (`List`, `ListAll`, `ListMeta`, `Due`, `Agenda`), remplacer `Format.tasks(shown, opts)` par `Format.render(shown, opts)`. `due --json` : liste de maps avec champ `"bucket"` (`Map.put(Format.task_map(t), :bucket, Query.due_bucket(t, today))`). `listproj`/`listcon --json` : `Jason.encode!(vals)`.

README : usage (`todo add`, `ls`, `do`, flags, variables d'env, chemins XDG, extensions `due:`/`recur:`/`t:`), build (`mix escript.build`), install (`mix escript.install`).

- [ ] **Step 4: Run** → PASS.

- [ ] **Step 5: Vérification finale**

```bash
mix test && mix format --check-formatted && mix escript.build
dir=$(mktemp -d) && export TODOTXT_DIR=$dir
./todo add "tester le binaire +demo" && ./todo ls && ./todo do 1 && ./todo --json ls
```

Expected : tout vert, le binaire fonctionne end-to-end sur un vrai `TODOTXT_DIR`.

- [ ] **Step 6: Commit** — `"JSON output + README + release escript"`.

---

## Self-review notes

- Couverture spec : §3 parsing→Tasks 2-3, §4 commandes→Tasks 5-12, §5 fichiers→Task 4, §6 erreurs→Helpers/dispatch, §7 tests→par tâche, extensions→Tasks 6 (t:), 9 (recur:), 11 (due:).
- Hors scope confirmé : TUI, addons réels (`listaddons` stub), sync.
