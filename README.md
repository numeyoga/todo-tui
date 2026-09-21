# TodoTxt

A command-line [todo.txt](http://todotxt.org/) manager written in Elixir,
distributed as a single `todo` escript. Feature parity with `todo.sh`
plus the modern `due:`, `recur:` and `t:` extensions, XDG file
locations, colored output and a `--json` mode for scripting.

## Build & install

Requires Elixir ~> 1.18 and Erlang/OTP.

```sh
mix deps.get
mix escript.build        # produces ./todo
./todo help

# or install into ~/.mix/escripts (make sure it's on your PATH)
mix escript.install
```

Full user documentation (in French): [docs/GUIDE.md](docs/GUIDE.md).

## Usage

```
todo [--file PATH] [--done-file PATH] [--plain] [--json] COMMAND [ARGS...]
```

### Adding & editing

| Command | Description |
|---|---|
| `add\|a TEXT...` | Add a task (creation date = today) |
| `append\|app N TEXT...` | Append text to task N |
| `prepend\|prep N TEXT...` | Prepend text to task N |
| `replace N TEXT...` | Replace task N's text |
| `edit` | Open `todo.txt` in `$EDITOR` |

### Lifecycle

| Command | Description |
|---|---|
| `do N` | Mark task N done (spawns the next occurrence if it has `recur:`) |
| `undo N` | Reopen task N |
| `del\|rm N [TERM]` | Delete task N, or strip TERM from its text |
| `pri N X` / `depri N` | Set / remove priority (`A`-`Z`) |
| `move\|mv N done\|todo` | Move task N between `todo.txt` and `done.txt` |

### Listing

| Command | Description |
|---|---|
| `ls\|list [TERMS...]` | Visible tasks sorted by priority then line — done tasks shown dimmed, future `t:` hidden. TERMS are AND-ed; `+proj` and `@ctx` match exactly, anything else is a substring match |
| `listall\|lsa` | All tasks from `todo.txt` **and** `done.txt` |
| `listproj\|lsprj` | Unique `+projects` across both files |
| `listcon\|lsc` | Unique `@contexts` across both files |
| `listpri\|lspr P` | Tasks at priority `P` (`todo.txt` only) |
| `due` | Open tasks bucketed as OVERDUE / TODAY / THIS WEEK / LATER by `due:` |
| `agenda` | Next 14 days of `due:` dates, plus upcoming `t:` thresholds |

### Maintenance & meta

| Command | Description |
|---|---|
| `archive` | Move `x`-completed tasks to `done.txt` |
| `dedupe` | Remove duplicate lines from `todo.txt` |
| `report` | Append `"DATE <open> <done>"` to `report.txt` |
| `listaddons` | List addons (unsupported stub) |
| `help`, `-h` | Command summary |
| `--version` | Print version |

## Global flags

| Flag | Effect |
|---|---|
| `-f`, `--file PATH` | Use PATH as `todo.txt` |
| `-d`, `--done-file PATH` | Use PATH as `done.txt` |
| `--plain` | Disable ANSI colors |
| `--json` | Emit JSON on `ls`, `listall`, `due`, `agenda`, `listproj`, `listcon` |
| `-h` | Help |

Task lines are printed as `N: <raw line>` where `N` is the **file line
number** — stable under filtering, and what `do`/`del`/`pri`/… take as
argument. Done tasks are dimmed; `(A)`/`(B)`/`(C)` priorities are
colored red/yellow/cyan.

## File locations

Paths are resolved in this order (first wins):

1. CLI flags `-f` / `--done-file`
2. Env vars `TODOTXT_TODO_FILE`, `TODOTXT_DONE_FILE`
3. `TODOTXT_DIR` (applies to both files and `report.txt`)
4. `TODO_DIR=` in the config file `$XDG_CONFIG_HOME/todotxt/config`
   (`KEY=value` lines)
5. XDG default: `$XDG_DATA_HOME/todo/` (i.e. `~/.local/share/todo/`)

`done.txt` can be relocated independently via `-d` /
`TODOTXT_DONE_FILE`; `report.txt` follows the data directory
(`TODOTXT_DIR` / `TODO_DIR` / XDG).

### Environment variables

| Variable | Effect |
|---|---|
| `TODOTXT_DIR` | Directory holding `todo.txt`, `done.txt`, `report.txt` |
| `TODOTXT_TODO_FILE` | Explicit path to `todo.txt` |
| `TODOTXT_DONE_FILE` | Explicit path to `done.txt` |
| `NO_COLOR` | When set (any value), disables colors |
| `TERM` | `dumb`/unset also disables colors |
| `EDITOR` | Editor for `todo edit` |

## Extensions

Standard todo.txt fields are fully supported: `x` done marker,
`YYYY-MM-DD` completion/creation dates, `(A)` priorities, `+projects`,
`@contexts` and `key:value` tags. On top of that:

| Tag | Meaning |
|---|---|
| `due:YYYY-MM-DD` | Due date; drives `due` buckets and `agenda` |
| `t:YYYY-MM-DD` | Threshold: task is hidden from `ls` until that date |
| `recur:[+]N<d\|w\|m\|y>` | Recurrence. `do` on such a task appends the next occurrence with a recomputed `due:`. `recur:+1w` shifts from the **completion** date; `recur:1w` (strict) shifts from the previous `due:` date |

## JSON output

`--json` is accepted by `ls`, `listall`, `due`, `agenda`, `listproj`
and `listcon` (`listpri` stays text-only). Tasks are emitted as
objects:

```json
{
  "line": 1,
  "done": false,
  "priority": "A",
  "completion_date": null,
  "creation_date": "2026-09-21",
  "description": "call mom +fam @phone due:2026-09-25",
  "projects": ["+fam"],
  "contexts": ["@phone"],
  "tags": {"due": "2026-09-25"}
}
```

Per-command shapes:

- `ls`, `listall`: array of task objects.
- `due`: flat array of task objects, each with an extra
  `"bucket": "overdue"|"today"|"week"|"later"` field (tasks without a
  valid `due:` are excluded).
- `agenda`: `{"dates": {"YYYY-MM-DD": [tasks…]}, "thresholds": [tasks…]}`.
- `listproj`, `listcon`: array of strings.

All JSON output is pretty-printed; pipe through `jq` for scripting.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Error (bad task number, unreadable file, …) — message on stderr as `todo: …` |
| 2 | Usage error — message on stderr as `usage: …` |

## Development

```sh
mix test                       # test suite
mix format --check-formatted   # formatting
mix escript.build              # release build → ./todo
```
