# Spec — TUI term_ui pour todotxt (v1.1)

Date : 2026-09-21
Statut : design validé section par section (brainstorming superpowers)

## 1. Intention

Ajouter l'interface TUI prévue en v1.1 par le spec v1 : un adaptateur
interactif au-dessus de `Store`/`Query`/`Task`, lancé par `todo --tui`,
basé sur [`term_ui`](https://github.com/agentjido/term_ui) `~> 1.0`.

Décisions de scope actées :

- **Périmètre : gestion complète** — toutes les opérations usuelles du
  CLI sont accessibles depuis le TUI (voir §5)
- **Entrée : flag global `--tui`** — `todo --tui [-f FILE] [-d FILE] [--plain]`
- **Layout : sidebar + liste + détail** (style lazygit, 3 panes)
- **Données : vues Todo + Done + Agenda**
- **Fichier modifié de l'extérieur : auto-reload** par poll mtime (~2 s)
  avec garde anti-écrasement
- **`edit` via `$EDITOR` : inclus** — mécanisme quit → edit → relaunch (§7)
- **Couche mutation : extraction de `TodoTxt.Ops`** — opérations pures
  partagées CLI + TUI ; `Commands.*` deviennent des coquilles de formatage.
  Le comportement externe du CLI reste identique (garanti par la suite
  de tests existante)

Dépendance : `{:term_ui, "~> 1.0"}` (1.0.0 publiée 2026-08-31 ;
Elixir 1.15+ requis — projet en ~> 1.18 ✓ ; OTP 26+ backend TTY,
OTP 28+ backend Raw).

## 2. Architecture

```
lib/todotxt/
  ops.ex           # NOUVEAU — opérations métier pures partagées CLI+TUI
  commands/        # refactorés : Ops → Store → formatage (inchangé ext.)
  tui.ex           # NOUVEAU — app Elm : init/event_to_msg/update/view + run loop
  tui/state.ex     # NOUVEAU — %Tui.State{} + helpers purs (sélection, filtres)
  tui/view.ex      # NOUVEAU — rendu des 3 panes + dialogues modaux
  tui/keys.ex      # NOUVEAU — table keybinding → msg
```

Flux :

```
key/mouse event ──event_to_msg──► msg ──update──► {state', commands}
                                       │
                    ┌──────────────────┤
                    ▼                  ▼
              Ops.* (pur)        commands term_ui :
                    │            - write/read fichiers (via Task + send_message)
                    ▼            - timer (tick mtime ~2 s, réarmé)
              state.tasks'       - quit
                    │
                    ▼
                 view(state) → sidebar | liste | détail
```

Principes :

- `update/2` reste pur : il renvoie des commands term_ui pour les effets.
  Les I/O fichiers passent par un `Task` applicatif qui renvoie le
  résultat via `TermUI.Runtime.send_message/3` (pattern documenté
  term_ui 1.0 ; pas de commande générique « function » dans l'API).
- `Tui.State`, `Tui.View`, `Tui.Keys`, `Ops` sont testables sans terminal.
- `todo --tui` est dispatché par `CLI.run_command/2` comme les autres
  commandes, mais n'appelle `System.halt` qu'au retour du runtime.
  `Tui.run/2` accepte le même `env` injectable (`paths`, `today`,
  `root_module`) pour les tests.

## 3. `TodoTxt.Ops` — couche mutation partagée

Fonctions pures sur `[%Task{}]` — aucune I/O, aucune string de sortie :

```elixir
add(tasks, text, today)                       :: {:ok, tasks', new_task}
complete(tasks, line, today)                  :: {:ok, tasks', recur | nil} | {:error, msg}
uncomplete(tasks, line)                       :: {:ok, tasks'} | {:error, msg}
delete(tasks, line)                           :: {:ok, tasks'} | {:error, msg}
delete_term(tasks, line, term)                :: {:ok, tasks'} | {:error, msg}
set_priority(tasks, line, prio | nil)         :: {:ok, tasks'} | {:error, msg}
set_text(tasks, line, text)                   :: {:ok, tasks'} | {:error, msg}
append_text(tasks, line, text)                :: {:ok, tasks'} | {:error, msg}
prepend_text(tasks, line, text)               :: {:ok, tasks'} | {:error, msg}
move(tasks, done, line, :done | :todo)        :: {:ok, tasks', done'} | {:error, msg}
archive(tasks, done)                          :: {:ok, tasks', done'}
dedupe(tasks)                                 :: {:ok, tasks'}
```

`dedupe` est partagé dans `Ops` (dédup en conservant l'ordre, comme
`Commands.Dedupe`) mais n'a pas de keybinding TUI — maintenance batch,
le CLI reste son interface.

- `complete` retourne l'éventuelle occurrence `recur:` (logique actuelle
  de `Commands.Do` : numéro = `max(line) + 1`, validation `recur:` →
  `{:error, _}` avant toute écriture)
- `move` renvoie les deux listes mises à jour — l'appelant fait les deux
  `Store.write`
- Refactor : chaque `Commands.*` concerné appelle `Ops` puis formate son
  message exactement comme aujourd'hui. Aucun changement de comportement ;
  les tests `commands/*_test.exs` et `cli_test.exs` existants doivent
  rester verts sans modification.

## 4. État et modèle Elm

```elixir
%TodoTxt.Tui.State{
  paths: %{todo:, done:, report:},
  today: Date.t(),
  tasks: [Task.t()],            # todo.txt
  done_tasks: [Task.t()],       # done.txt
  view: :todo | :done | :agenda,
  focus: :sidebar | :list,      # le pane détail est passif
  sidebar_idx: non_neg_integer(),
  list_idx: non_neg_integer(),
  filter_terms: [String.t()],   # sélection sidebar + saisie /
  mode: :normal | :input,
  modal: nil | %{action: :add | :edit | :append | :prepend | :pri | :del | :archive,
                 input: term()},  # état du widget TextInput/PickList actif
  toasts: [toast],
  mtimes: %{todo: term(), done: term()},
  status: nil | String.t(),
  pending_write: boolean()       # garde anti-écrasement (§7)
}
```

Messages principaux : `{:nav, :up | :down}`, `:focus_next | :focus_prev`,
`:apply_sidebar`, `{:open_modal, action}`, `{:modal_input, ev}`,
`:modal_submit | :modal_cancel`, `:toggle_done`, `:move`, `:tick`,
`{:fs_changed, :todo | :done}`, `{:reloaded, tasks', done'}`,
`{:op_done, op, result}`, `:edit_external`, `:quit`.

La sidebar est data-driven : `Toutes` · `── Projets ──` (+proj triés,
avec compteurs) · `── Contextes ──` (@ctx idem) · `── Vues ──` Agenda ·
Done. `Enter` sur un item projet/contexte toggle le terme dans
`filter_terms` ; sur Agenda/Done bascule `view`.

## 5. Vues et interactions

**Pane liste** (selon `view`) :

- `:todo` — `Query.visible |> Query.filter |> Query.sort` ; ligne =
  `N: rendu` (numéro de ligne fichier, convention CLI), priorité
  colorée (A rouge / B jaune / C cyan, identique CLI), faites dimmed
- `:agenda` — sections OVERDUE / dates des 14 prochains jours / seuils
  `t:` à venir (mêmes données que `Commands.Agenda`)
- `:done` — `done_tasks`, plus récentes en tête

La **statusline** affiche en permanence les `filter_terms` actifs
(`filter: +fam @phone`), les compteurs (n tâches · m faites) et les
bindings principaux.

**Pane détail** : ligne, priorité, dates création/complétion, `due:`,
`t:`, `recur:`, projets, contextes, `raw` complet.

**Keybindings** (mode `:normal`, table centralisée dans `tui/keys.ex`) :

| Touche | Action | Touche | Action |
|---|---|---|---|
| `j/k`, `↓/↑` | naviguer | `x`, `espace` | do / undo |
| `Tab`, `h/l` | focus sidebar ↔ liste | `d` | supprimer (AlertDialog) |
| `Enter` | appliquer item sidebar | `p` | priorité (PickList A–Z + ∅) |
| `a` | ajouter (TextInput) | `m` | move todo ↔ done |
| `e` | éditer texte (TextInput pré-rempli) | `E` | `$EDITOR` sur todo.txt (§7) |
| `A` / `P` | append / prepend (TextInput) | `R` | archive (AlertDialog) |
| `/` | filtre texte libre | `r` | reload manuel |
| `Esc` | annuler modal / effacer filtre | `?` / `q` | aide / quitter |

**Modales** (mode `:input`, widgets term_ui) : `TextInput` pour
add/edit/append/prepend et `/` (pré-rempli pour edit/append/prepend) ;
`PickList` pour la priorité ; `AlertDialog` pour del/archive. `Enter`
valide → `Ops` → write → reload ; `Esc` annule. Erreur `Ops`/`Store` →
toast rouge, modal conservée ouverte pour correction.

## 6. Erreurs et feedback

- `{:error, msg}` métier → toast + statusline, état inchangé
- `Store.write` en échec → toast + `Store.read` (fichier fait foi)
- Mutation sur une liste vide / index invalide → no-op (ou toast si
  l'action présuppose une sélection)
- Toutes les réécritures passent par `Store.write/2` → `write_atomic`
  existant ; jamais de write partiel

## 7. Cycle de vie : watch, $EDITOR, quit

**Watch externe** : commande timer réarmée (~2 s) → msg `:tick` →
`File.stat` mtime de todo.txt/done.txt. Si mtime ≠ `mtimes` →
`Store.read` ×2 → `{:reloaded, …}` + toast « fichier rechargé ».
Garde : `pending_write` = true entre l'émission d'une mutation et le
`:reloaded` consécutif ; un `:tick` pendant `pending_write` est ignoré.
Après chaque write local réussi on met à jour `mtimes` → pas de reload
parasite de nos propres écritures. Conflit réel : le write local gagne,
le reload suivant ramène l'état fichier.

**`$EDITOR` (`E`)** : term_ui 1.0 n'a pas de primitive suspend/exec.
Mécanisme retenu — *quit → edit → relaunch* :

1. `update` marque `edit_external: true` et renvoie `Command.quit()`
2. `Tui.run/1` récupère la raison de sortie (flag ETS posé avant quit —
   détail d'implémentation à valider sur l'API exacte du runtime)
3. `TodoTxt.Editor.open(paths.todo)` dans le terminal restauré —
   amendement 2026-09-22 : port `:nouse_stdio` (vrai tty pour vim/nano),
   `VISUAL` > `EDITOR` > `vi`, arguments supportés (`code --wait`)
4. Relance `TermUI.Runtime.run(root: Tui)` avec l'état restauré
   (view/filtres/sélection si encore valides)

Boucle dans `Tui.run` : `run → raison → éventuellement edit → run`…
jusqu'à quit normal → `{:ok, nil}` pour `CLI`.

**Quit** : `q` → `Command.quit()` → retour CLI exit 0.

## 8. Tests

- `ops_test.exs` — chaque op pure sur `%Task{}` construits ; parité avec
  les cas des tests commands existants (recur, numérotation, erreurs)
- `tui/state_test.exs` — helpers purs (sélection bornée, filtres sidebar,
  construction des entrées de sidebar avec compteurs)
- `tui_test.exs` — `update`/`event_to_msg` : injecter des `Event.Key{}`,
  asserter transitions d'état, messages, commands émises ; `Ops` et I/O
  via injection (env) — pas de vrai fichier
- `cli_test.exs` — `--tui` accepté par le parser, dispatch vers Tui
  (root_module injecté → module factice qui retourne quit immédiat ;
  term_ui 1.0 documente `skip_terminal: true` + `Runtime.sync/2` pour
  ce genre de test)
- Suite commands existante : verte sans modification (preuve de non-
  régression du refactor Ops)
- Smoke manuel : `mix escript.build && ./todo --tui`

## 9. Hors scope v1.1

- `report`, `listaddons`/addons, `dedupe` côté TUI (partagé dans Ops,
  sans keybinding), `move` par drag & drop
- Édition multi-ligne, undo global (Ctrl-Z), macros
- Souris au-delà de la sélection/clic (scroll pane à pane si gratuit)
- Thèmes multiples : thème unique. (`--plain` → rendu monochrome :
  implémenté 2026-09-22 — attributs gras/estompé/inversé, aucune
  couleur ; `--plain`, `COLORS=off`, `NO_COLOR`, `TERM=dumb`)
- Backend SSH term_ui, exécution dans IEx
- Synchronisation multi-instances au-delà du watch mtime
