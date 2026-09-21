# Spec — CLI todo.txt en Elixir

Date : 2026-09-21
Statut : approuvé en design review (brainstorming superpowers)

## 1. Intention

CLI distribuable de gestion de todos au format [todo.txt](https://github.com/todotxt/todo.txt),
avec parité fonctionnelle avec `todo.sh` + extensions modernes (`due:`, `recur:`, `t:`).
Projet autonome, publiable. v1 = CLI complet + sortie JSON ; un TUI suivra en v1.1
(architecture pensée pour, mais hors scope v1).

Décisions de scope actées :

- Stack : **Elixir**, projet `mix`, binaire `escript`
- Périmètre : **parité `todo.sh`** + extensions `due:` / `recur:` / `t:`
- Fichiers : **XDG compliant** (`$XDG_DATA_HOME/todo/`, config `$XDG_CONFIG_HOME/todotxt/`)
- Interaction : CLI pur + `--json` ; TUI reporté post-v1

Nom de travail : application `TodoTxt`, binaire `todo` (modifiable avant scaffolding).

## 2. Architecture

```
lib/todotxt/
  task.ex        # struct %Task{} + règles métier (complete, set_priority, recur…)
  parser.ex      # ligne todo.txt ↔ %Task{}, sérialisation canonique
  store.ex       # lecture/écriture fichiers, write_atomic, résolution des paths
  query.ex       # filtres + tris purs sur [%Task{}] (projet, contexte, prio, due…)
  format.ex      # rendu texte (couleurs) et --json
  commands/      # un module par commande : add.ex, list.ex, do.ex, pri.ex…
  cli.ex         # parsing argv, flags globaux, dispatch → Commands, exit codes
  config.ex      # XDG paths + fichier de config + env vars TODOTXT_*
```

Principes :

- Logique métier pure : `Commands.*` et `Query` opèrent sur des listes de `%Task{}` —
  aucun I/O en dehors de `Store` et `CLI`.
- `Store` reçoit une map `paths` injectable (`%{todo:, done:, report:}`) — convention
  reprise de `expense_tracker` (`run/2`), tests sans toucher aux vrais fichiers.
- `CLI.main/1` est le seul endroit qui appelle `System.halt` ; tout le reste remonte
  `{:error, msg}` → stderr + exit code (1 métier, 2 usage — cf. §6).
- Le futur TUI = nouvel adaptateur au-dessus de `Store`/`Query`/`Task`, sans refacto du CLI.

## 3. Modèle de données

```elixir
%Task{
  line: 3,                    # numéro de ligne dans le fichier (référence stable)
  raw: "...",                 # ligne originale
  done: false,
  completion_date: nil,       # ~D[2026-09-21] si "x 2026-09-21"
  priority: nil,              # ?A..?Z
  creation_date: nil,         # ~D[...] si présente
  description: "...",
  projects: ["+projet"],      # ordre d'apparition
  contexts: ["@contexte"],
  tags: %{"due" => "2026-09-25", "recur" => "+1w", "t" => "..."}
}
```

### Parsing (spec todo.txt officielle)

- `(A)` en tête de ligne = priorité, uniquement sur tâche non complétée
- `x` + date optionnelle en tête = tâche faite ; `x` seul accepté
- date de création juste après la priorité ou le `x`+complétion
- `+projet` / `@contexte` = tokens délimités par espaces, n'importe où dans la description
- `cle:valeur` = tags ; `due:`, `recur:`, `t:` reconnus comme extensions
- Sérialisation canonique : `x <complétion> (<prio>) <création> <description avec tags>`

### Extensions

- `due:AAAA-MM-JJ` — échéance
- `recur:+1d|2w|3m|1y` — relatif à la date de complétion ; `recur:1w` — strict depuis `due:`
- `t:AAAA-MM-JJ` — seuil : tâche masquée du `ls` par défaut avant cette date
- Marquer une tâche `recur:` comme done crée automatiquement l'occurrence suivante
  (priorité, projets, contextes, autres tags conservés ; `due:`/`t:` recalculés)

## 4. Commandes (parité `todo.sh`)

| Groupe | Commandes |
|---|---|
| Ajout/édition | `add` (alias `a`), `append`, `prepend`, `replace`, `edit` (ouvre `$EDITOR`) |
| Cycle de vie | `do` (marque fait, gère `recur:`), `undo` (rouvre une tâche), `del`/`rm`, `pri`/`depri`, `move`/`mv` |
| Listage | `ls`/`list` (tri priorité→ligne, filtres par terme/+projet/@contexte), `listall` (todo+done), `listproj`, `listcon`, `listpri` |
| Extensions | `due` (par échéance : overdue/today/week), `agenda` (due: + t: à venir) |
| Maintenance | `archive` (déplace les `x` vers done.txt), `dedupe`, `report` (append dans report.txt) |
| Méta | `help`, `--version`, `listaddons` (stub) |

Flags globaux : `-f/--file`, `-d/--done-file`, `--plain` (pas de couleurs),
`--json` (sur `ls`/`listall`/`due`/`agenda`/`listproj`/`listcon`), `-h`.

Numérotation : les numéros affichés sont les index de ligne du fichier — stables même
sous filtre ; `do`/`del`/`pri` réfèrent toujours ces index (convention expense_tracker).

## 5. Fichiers et configuration

Résolution des paths, premier qui gagne :

1. Flags CLI (`-f`, `-d`)
2. Env vars `TODOTXT_TODO_FILE`, `TODOTXT_DONE_FILE`
3. `$XDG_DATA_HOME/todo/` (`~/.local/share/todo/` par défaut) :
   `todo.txt`, `done.txt`, `report.txt`

Fichier de config optionnel `$XDG_CONFIG_HOME/todotxt/config` (format `KEY=value`
type todo.cfg) : couleurs on/off, tri par défaut de `ls`.

Comportement `do` : préfixe `x AAAA-MM-JJ` en place (comme todo.sh). `archive` déplace
les lignes `x` vers `done.txt`. `report` append des stats datées dans `report.txt`.

## 6. Gestion d'erreurs

- `{:error, "msg"}` métier → stderr + exit 1 (convention expense_tracker)
- Cas d'erreur explicites : numéro de ligne invalide, syntaxe invalide sur
  `pri`/`replace`/`move`, fichier illisible, `due:`/`recur:`/`t:` malformés
- Messages avec l'entrée fautive ; exit 2 pour erreur d'usage (mauvais args)
- Toute réécriture complète de fichier via `Store.write_atomic/2` (tmp + rename)

## 7. Tests

- `parser_test.exs` — golden tests depuis les exemples officiels de la spec todo.txt
  (cas limites : `(A)` pas en tête, dates partielles, tags multiples, `x` seul)
- `commands/*_test.exs` — chaque commande sur fichiers temporaires via `paths`
  injecté ; état fichier avant/après, pas de mocks
- `cli_test.exs` — intégration via `main/1` + `capture_io`, exit codes, `--json`
  décodé et asserté
- `task_test.exs` — règles métier pures (recur → occurrence suivante, depri, undo)
- TDD par incrément ; `mix test` vert avant chaque commit ; `mix format` standard

## 8. Hors scope v1

- TUI (v1.1 — adaptateur au-dessus de Store/Query/Task)
- Addons/`~/.todo.actions.d` (`listaddons` est un stub)
- Sync, backends distants
