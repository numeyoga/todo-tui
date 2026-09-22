# Guide utilisateur — `todo`

`todo` est un gestionnaire de tâches en ligne de commande au format
[todo.txt](http://todotxt.org/), compatible avec `todo.sh` et doté
d'extensions modernes (`due:`, `recur:`, `t:`), de sorties JSON, d'une
interface interactive plein écran (`--tui`) et d'emplacements de
fichiers conformes XDG.

---

## 1. Installation

### Depuis les sources

Prérequis : Elixir ~> 1.18 et Erlang/OTP.

```sh
git clone <url-du-depot> todotxt
cd todotxt
mix deps.get
mix escript.build      # produit l'exécutable ./todo
./todo help
```

### Installation dans le PATH

```sh
mix escript.install    # installe dans ~/.mix/escripts
```

Assurez-vous que `~/.mix/escripts` est dans votre `PATH`. Vous pouvez
aussi simplement copier le fichier `todo` n'importe où — c'est un
escript autonome (Erlang/OTP doit être installé sur la machine).

### Vérification

```sh
todo --version     # todo 0.1.0
todo help          # résumé des commandes
```

---

## 2. Démarrage rapide

```sh
# Ajouter des tâches — la date de création est ajoutée automatiquement
todo add "ranger le bureau +maison"
todo add "(A) appeler mamie +fam @phone due:2026-09-22"
todo add "renouveler le domaine +admin due:2026-09-19 recur:+1m"

# Lister (tri : priorité puis numéro de ligne)
todo ls

# Marquer la tâche 1 comme faite
todo do 1

# Les tâches en retard / du jour / de la semaine
todo due

# Les 14 prochains jours, plus les seuils t: à venir
todo agenda

# Archiver les tâches faites vers done.txt
todo archive

# Interface interactive plein écran (section 6)
todo --tui
```

---

## 3. Le format todo.txt en 2 minutes

Chaque ligne de `todo.txt` est une tâche. Anatomie d'une ligne complète :

```
x 2026-09-21 (A) 2026-09-20 Appeler mamie +fam @phone due:2026-09-22
│      │       │       │           │         │      │        │
│      │       │       │           │         │      │        └─ tag due:
│      │       │       │           │         │      └─ contexte @phone
│      │       │       │           │         └─ projet +fam
│      │       │       │           └─ description (texte libre + métadonnées)
│      │       │       └─ date de création (optionnelle)
│      │       └─ priorité (A)–(Z), uniquement sur tâche ouverte
│      └─ date de complétion (optionnelle)
└─ « x » en début de ligne = tâche terminée
```

Règles essentielles :

- **`(A)` à `(Z)`** : priorité, reconnue uniquement en tout début de
  ligne d'une tâche non terminée.
- **`x `** en début de ligne : tâche terminée, suivie
  optionnellement de sa date de complétion.
- **Dates** : toujours au format ISO `AAAA-MM-JJ`.
- **`+projet`**, **`@contexte`** : un mot commençant par `+` ou `@`,
  n'importe où dans la description.
- **`cle:valeur`** : tags libres ; `due:`, `recur:` et `t:` ont un
  comportement spécial (section 7).

Le fichier est un texte brut : vous pouvez l'éditer à la main ou avec
`todo edit`. Les lignes vides sont ignorées.

> Si votre texte de tâche commence par un tiret ou ressemble à une
> option, séparez-le par `--` :
> `todo add -- "- relire le rapport"`

---

## 4. Les numéros de tâches

`todo` référence les tâches par leur **numéro de ligne physique** dans
`todo.txt`. L'affichage les préfixe `N: ` :

```
2: (A) 2026-09-21 appeler mamie +fam @phone due:2026-09-22
3: 2026-09-21 renouveler le domaine +admin due:2026-09-19 recur:+1m
```

Ces numéros sont **stables sous filtre** : `todo ls +admin` affiche la
ligne 3 comme `3:`, pas `1:`. Toutes les commandes qui prennent un
`N` (`do`, `del`, `pri`, `append`…) attendent ce numéro de ligne.

Après `archive` ou `del`, les lignes sont supprimées du fichier :
relancez `todo ls` avant de manipuler à nouveau les numéros.

---

## 5. Référence des commandes

### Ajout et édition

| Commande | Effet |
|---|---|
| `todo add TEXT...` (alias `a`) | Ajoute une tâche, date de création = aujourd'hui. Un `(X)` initial est conservé en tête, avant la date. |
| `todo append N TEXT...` (`app`) | Ajoute TEXT à la fin de la ligne N. |
| `todo prepend N TEXT...` (`prep`) | Insère TEXT en tête de la ligne N. |
| `todo replace N TEXT...` | Remplace toute la ligne N ; le texte est re-parsé (`x`, `(A)`, dates honorés). |
| `todo edit` | Ouvre `todo.txt` dans `$EDITOR`. |

Exemples :

```sh
todo add "(A) déposer le colis +courses @ville"
todo append 3 "due:2026-09-30"        # ajoute une échéance à la tâche 3
todo prepend 2 "(B)"                  # repriorise en tête de ligne
todo replace 5 "(C) 2026-09-21 nouveau texte +projet"
```

### Cycle de vie

| Commande | Effet |
|---|---|
| `todo do N` | Marque N faite : préfixe `x <date-du-jour>`. Si la tâche a `recur:`, la prochaine occurrence est ajoutée en fin de fichier. |
| `todo undo N` | Rouvre N : retire `x` et la date de complétion. |
| `todo del N` (`rm`) | Supprime la ligne N. |
| `todo del N TERM` | Retire TERM de la description de N (ex. `todo del 2 +projet`). |
| `todo pri N X` | Donne la priorité `X` (A–Z) à la tâche N. |
| `todo depri N` | Retire la priorité de N. |
| `todo mv N done` (`move`) | Déplace la ligne N de `todo.txt` vers la fin de `done.txt`. |
| `todo mv N todo` | Déplace la ligne N de `done.txt` vers `todo.txt`. |

```sh
todo do 2            # 2: x 2026-09-21 (A) 2026-09-20 appeler mamie …
todo undo 2          # rouvre la tâche
todo pri 3 B         # 3: (B) 2026-09-21 renouveler le domaine …
todo del 4 +travail  # retire le tag +travail de la tâche 4
```

### Listage

| Commande | Effet |
|---|---|
| `todo ls [TERMES...]` (`list`) | Tâches visibles de `todo.txt`, triées par priorité puis ligne. Les tâches faites s'affichent estompées en bas ; celles dont le `t:` est dans le futur sont masquées. |
| `todo listall` (`lsa`) | Toutes les tâches de `todo.txt` **et** `done.txt`. |
| `todo listproj` (`lsprj`) | Projets `+…` uniques présents dans les deux fichiers. |
| `todo listcon` (`lsc`) | Contextes `@…` uniques. |
| `todo listpri P` (`lspr`) | Tâches de priorité `P` (dans `todo.txt`). |
| `todo due` | Tâches ouvertes avec `due:`, groupées : OVERDUE / TODAY / THIS WEEK / LATER. |
| `todo agenda` | Les 14 prochains jours par date de `due:`, puis une section `THRESHOLDS:` pour les `t:` à venir dans la même fenêtre. |

Filtrage de `ls` : les termes sont combinés en **ET**. `+projet` et
`@contexte` correspondent exactement ; tout autre terme est une
sous-chaîne de la ligne.

```sh
todo ls +fam @phone       # tâches du projet +fam ET du contexte @phone
todo ls mamie             # sous-chaîne « mamie »
todo lspr A               # uniquement les priorités A
```

Exemple de sortie de `due` :

```
OVERDUE:
3: 2026-09-21 renouveler le domaine +admin due:2026-09-19 recur:+1m

THIS WEEK:
2: (A) 2026-09-21 appeler mamie +fam @phone due:2026-09-22
```

### Maintenance et divers

| Commande | Effet |
|---|---|
| `todo archive` | Déplace toutes les lignes `x …` de `todo.txt` vers `done.txt`. |
| `todo dedupe` | Supprime les lignes dupliquées de `todo.txt`. |
| `todo report` | Ajoute `AAAA-MM-JJ <ouvertes> <faites>` à `report.txt`. |
| `todo edit` | Ouvre `todo.txt` dans `$EDITOR`. |
| `todo help`, `todo -h` | Aide. Ne lit pas les fichiers. |
| `todo --version` | Version. |
| `todo listaddons` | Extensions externes : non supportées (stub de compatibilité todo.sh). |

---

## 6. L'interface interactive (`--tui`)

`todo --tui` lance une interface plein écran dans le terminal. C'est un
**mode autonome**, pas une commande : il n'accepte aucun argument de
commande — `todo --tui ls` est une erreur d'usage
(`usage: --tui takes no command`). Les fichiers sont résolus comme
d'habitude (`-f`, `-d`, variables d'environnement, config) ; si
`todo.txt` est illisible, l'erreur s'affiche avant le lancement de
l'interface. Les flags `--plain` et `--json` sont acceptés mais sans
effet dans le TUI.

### Disposition

Trois panneaux, plus une ligne de statut en bas :

- **Barre latérale** (gauche) : « Toutes » avec les compteurs
  ouvertes/total, puis les `+projets` et `@contextes` avec leur nombre
  d'occurrences, puis les vues **Agenda** et **Done**.
- **Liste** (centre) : les tâches au format `N: ligne brute`, avec les
  mêmes couleurs que `ls` (priorités `(A)`/`(B)`/`(C)`, tâches faites
  estompées).
- **Détail** (droite) : la ligne brute de la tâche sélectionnée, puis
  ses champs — ligne, priorité, dates de création et de complétion,
  `due:`, `t:`, `recur:`, projets, contextes.
- **Ligne de statut** : vue courante, filtres actifs
  (`filter: +projet @contexte`), messages d'action (`3: done`,
  `rechargé (fichier modifié)`…) et rappel des touches. C'est aussi là
  que s'ouvrent les saisies de texte.

### Les trois vues

| Vue | Contenu |
|---|---|
| **Todo** (défaut) | Tâches visibles de `todo.txt` — même tri que `ls` (priorité puis ligne), `t:` futurs masqués, filtres ET appliqués. |
| **Agenda** | Les 14 prochains jours groupés par `due:`, puis une section `THRESHOLDS:` pour les `t:` à venir. |
| **Done** | Le contenu de `done.txt`, lignes les plus récentes en premier. |

On change de vue via la barre latérale : `Tab` (ou `h`) pour lui donner
le focus, `j`/`k` pour s'y déplacer, `Entrée` pour appliquer — le focus
revient ensuite à la liste. Appliquer un projet ou un contexte
**bascule** le terme correspondant dans les filtres actifs (plusieurs
filtres se combinent en ET, comme les termes de `ls`) ; « Toutes »
réinitialise les filtres et ramène à la vue Todo. Le filtre `/` et les
filtres de la barre latérale ne s'appliquent qu'à la vue Todo.

### Raccourcis clavier

| Touche | Action |
|---|---|
| `j`/`k` ou `↓`/`↑` | Déplacer la sélection (liste ou barre latérale selon le focus) |
| `Tab` | Basculer le focus barre latérale ↔ liste ; `h` et `l` y vont directement |
| `Entrée` | Appliquer l'entrée de la barre latérale (filtre ou vue) |
| `Échap` | Effacer les filtres ; dans une saisie ou un dialogue, annuler |
| `x` ou `Espace` | Faire/défaire la tâche — en vue Done, la **rouvre** (décomplétée en fin de `todo.txt`) |
| `a` | Ajouter une tâche (saisie en ligne de statut, date de création = aujourd'hui) |
| `e` | Éditer la ligne brute de la tâche sélectionnée |
| `A` / `P` | Append / prepend du texte sur la tâche |
| `p` | Priorité : liste de choix `A`–`Z` ou « (aucune) » |
| `d` | Supprimer la tâche (dialogue de confirmation) |
| `m` | Déplacer la tâche entre `todo.txt` et `done.txt` (vues Todo et Done) |
| `R` | Archiver les tâches faites vers `done.txt` (confirmation) |
| `/` | Filtrer : termes séparés par des espaces, combinés en ET ; saisie vide = tout effacer |
| `E` | Quitter le TUI, ouvrir `todo.txt` dans `$EDITOR`, relancer le TUI |
| `r` | Recharger les fichiers immédiatement |
| `?` | Aide en ligne |
| `q` | Quitter |

Les touches `a`, `e`, `A`, `P` et `/` ouvrent une saisie dans la ligne
de statut — `Entrée` valide, `Échap` annule, un texte vide ne fait
rien (sauf `/` qui efface les filtres). Les touches `p`, `d`, `R` et
`?` ouvrent des boîtes de dialogue modales. Les mutations sont
identiques au CLI : `x` sur une tâche `recur:` ajoute l'occurrence
suivante en fin de fichier, `d` supprime la ligne physique, `m` fait la
paire append + suppression entre les deux fichiers. En vue **Done**,
`e`/`A`/`P`/`d`/`p`/`m` s'appliquent aux lignes de `done.txt` — les
numéros `N:` y sont ceux de `done.txt`, pas de `todo.txt`.

### Rechargement automatique et `$EDITOR`

Le TUI surveille les dates de modification (`mtime`) de `todo.txt` et
`done.txt` et recharge automatiquement ~2 s après une modification
externe — la ligne de statut affiche `rechargé (fichier modifié)`.
Limite connue : la détection repose **uniquement** sur le mtime ; une
écriture qui conserve le mtime passe inaperçue. `r` force alors le
rechargement.

`E` quitte le TUI, ouvre `todo.txt` dans `$VISUAL`/`$EDITOR` (défaut
`vi`), puis relance le TUI à la fermeture de l'éditeur — pratique pour
les retouches en vrac que `e` ne couvre pas. Si l'exécutable est
introuvable ou si l'éditeur échoue, l'erreur s'affiche sur stderr et le
TUI ne redémarre pas.

---

## 7. Extensions : `due:`, `recur:`, `t:`

### `due:AAAA-MM-JJ` — échéance

Alimente `todo due` (buckets) et `todo agenda` (calendrier 14 jours).
Une `due:` invalide ou absente exclut la tâche de ces vues.

### `t:AAAA-MM-JJ` — seuil (« tickler »)

La tâche est **masquée de `todo ls`** jusqu'à cette date, puis réapparaît
automatiquement. `todo agenda` liste les seuils des 14 prochains jours
sous `THRESHOLDS:`.

```sh
todo add "relancer le client t:2026-09-25 +travail"
```

### `recur:` — récurrence

Marquer une tâche `recur:` avec `do` ajoute automatiquement l'occurrence
suivante en fin de fichier, avec `due:` (et `t:` si présent) recalculés :

- **`recur:+1w`** (avec `+`) : la nouvelle `due:` est calculée **depuis
  la date de complétion** — « une semaine après que je l'ai faite ».
- **`recur:1w`** (strict) : calculée **depuis l'ancienne `due:`** —
  échéance calendaire fixe, même si vous êtes en retard.

Unités : `d` (jours), `w` (semaines), `m` (mois), `y` (années).
Exemples : `recur:+3d`, `recur:2w`, `recur:+1m`, `recur:1y`.

```sh
$ todo do 3
3: x 2026-09-21 2026-09-21 renouveler le domaine +admin due:2026-09-19 recur:+1m
5: 2026-09-21 renouveler le domaine +admin due:2026-10-21 recur:+1m
```

Une valeur `recur:` malformée produit une erreur sans toucher au fichier.

---

## 8. Fichiers et configuration

### Emplacements par défaut (XDG)

```
$XDG_DATA_HOME/todo/todo.txt      →  ~/.local/share/todo/todo.txt
$XDG_DATA_HOME/todo/done.txt      →  ~/.local/share/todo/done.txt
$XDG_DATA_HOME/todo/report.txt    →  ~/.local/share/todo/report.txt
$XDG_CONFIG_HOME/todotxt/config   →  ~/.config/todotxt/config
```

Les fichiers sont créés à la première écriture si nécessaire.

### Ordre de résolution des chemins

Le premier qui gagne :

1. Flags : `todo -f autre.txt ls`, `todo --done-file=archives.txt …`
2. Variables : `TODOTXT_TODO_FILE`, `TODOTXT_DONE_FILE`
3. `TODOTXT_DIR` : un répertoire pour `todo.txt` + `done.txt` + `report.txt`
4. `TODO_DIR=` dans le fichier de config
5. Défaut XDG ci-dessus

`--done-file` et `TODOTXT_DONE_FILE` permettent de placer `done.txt`
indépendamment de `todo.txt`. `report.txt` suit le répertoire de données
(`TODOTXT_DIR` / `TODO_DIR` / XDG).

### Fichier de config

`~/.config/todotxt/config`, format `CLE=valeur` :

```
TODO_DIR=/home/moi/todo
COLORS=off
LS_SORT=line
```

| Clé | Effet |
|---|---|
| `TODO_DIR` | Répertoire de données (équivalent de `TODOTXT_DIR`) |
| `COLORS=off` | Désactive les couleurs (équivalent de `--plain`) |
| `LS_SORT=line` | `ls`/`listall` triés par numéro de ligne, sans priorité |

### Couleurs

Priorités `(A)` rouge, `(B)` jaune, `(C)` cyan ; tâches faites
estompées. Désactivées par `--plain`, `COLORS=off`, `NO_COLOR` (toute
valeur) ou `TERM=dumb`/non défini.

---

## 9. Flags globaux

| Flag | Effet |
|---|---|
| `-f`, `--file PATH` | Fichier `todo.txt` à utiliser |
| `-d`, `--done-file PATH` | Fichier `done.txt` à utiliser |
| `--plain` | Pas de couleurs |
| `--json` | Sortie JSON (voir §10) |
| `--tui` | Interface interactive — aucune commande acceptée (voir §6) |
| `-h`, `--help` | Aide |
| `--version` | Version |
| `--` | Fin des options — le reste est du texte de tâche |

Les flags peuvent être placés **n'importe où** dans la ligne :

```sh
todo --json ls
todo ls --json
todo --file=perso.txt add "test"
todo add -- "texte commençant par --json"
```

---

## 10. Sortie JSON et scripting

`--json` est accepté par `ls`, `listall`, `due`, `agenda`, `listproj`
et `listcon`. (`listpri` reste en texte.) La sortie est indentée ;
passez par `jq` pour scripter.

Objet tâche :

```json
{
  "line": 2,
  "done": false,
  "priority": "A",
  "completion_date": null,
  "creation_date": "2026-09-21",
  "description": "appeler mamie +fam @phone due:2026-09-22",
  "projects": ["+fam"],
  "contexts": ["@phone"],
  "tags": {"due": "2026-09-22"}
}
```

Formes par commande :

- `ls`, `listall` : tableau d'objets tâche.
- `due` : tableau d'objets tâche avec un champ `"bucket"` ∈
  `"overdue" | "today" | "week" | "later"`.
- `agenda` : `{"dates": {"AAAA-MM-JJ": [tâches…]}, "thresholds": [tâches…]}`.
- `listproj`, `listcon` : tableau de chaînes.

Exemples :

```sh
todo ls --json | jq '.[].description'
todo due --json | jq '[.[] | select(.bucket == "overdue")]'
todo agenda --json | jq '.dates | keys'
todo listproj --json | jq -r '.[]'
```

---

## 11. Codes de sortie et erreurs

| Code | Signification |
|---|---|
| `0` | Succès |
| `1` | Erreur métier — `todo: …` sur stderr (numéro de ligne invalide, fichier illisible, `recur:` malformé…) |
| `2` | Erreur d'usage — `usage: …` sur stderr (arguments manquants ou invalides) |

Exemple exploitable en script :

```sh
if ! todo do 42; then
  echo "la tâche 42 n'existe pas" >&2
fi
```

---

## 12. Astuces et limites connues

- **Références stables** : les numéros sont les lignes du fichier ;
  après `del`/`archive`, relancez `ls` avant d'agir.
- **Lignes vides** : ignorées au parsing ; elles sont compactées en fin
  de fichier lors des ajouts.
- **`ls` affiche les tâches faites** (estompées, en bas) tant qu'elles
  sont dans `todo.txt` — utilisez `archive` pour les sortir.
- **`listall` ignore les termes de filtre** éventuels (limitation connue).
- **`do` sur une tâche déjà faite** rafraîchit sa date de complétion.
- **Écritures atomiques** : les réécritures passent par un fichier
  temporaire + renommage ; un `todo.txt` symboliquement lié est remplacé
  par un fichier régulier.
- **`VISUAL` / `EDITOR`** : `VISUAL` l'emporte sur `EDITOR`, défaut
  `vi`. Les arguments sont supportés (`EDITOR="code --wait"`,
  `emacs -nw`…) ; l'éditeur s'exécute avec le vrai terminal — vim et
  nano fonctionnent. Un éditeur qui rend la main immédiatement
  (`code` sans `--wait`) relance le TUI aussitôt.
- **Pas de transaction multi-fichiers** : si la seconde écriture d'un
  `mv`/`archive` échoue, la tâche peut exister en double — l'ordre des
  écritures garantit qu'elle n'est jamais perdue.
