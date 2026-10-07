# Format Todo.txt : Spécification officielle, extensions et écosystème d'addons

Ce document constitue la référence documentaire pour le format **Todo.txt**, ses règles officielles de structuration, ses extensions de métadonnées (*key:value tags*) et l'écosystème d'addons associés.

---

## 1. Principes fondamentaux & Spécification officielle

Le format Todo.txt a été créé par Gina Trapani et est maintenu sur le dépôt officiel [todotxt/todo.txt](https://github.com/todotxt/todo.txt).

### Philosophie
* **Texte brut (*plain text*)** : Indépendant de tout logiciel ou système d'exploitation, pérenne, léger et manipulable avec des outils CLI standard (`grep`, `sort`, `sed`, `awk`, éditeurs de texte).
* **Une ligne = une tâche** : Chaque ligne non vide du fichier `todo.txt` correspond exactement à un élément de travail.
* **Triabilité native** : La position des préfixes permet aux utilitaires de tri alphabétique standards de produire un affichage logique sans analyse syntaxique complexe.

---

### Règles du format pour les tâches en cours (*Incomplete Tasks*)

Une tâche en cours s'organise autour de 3 règles syntaxiques :

1. **Règle 1 : La priorité (si présente) apparaît toujours au tout début**
   - Syntaxe : une lettre majuscule entre parenthèses suivie d'un espace, de `(A)` à `(Z)`.
   - *Exemple valide :* `(A) Réviser le contrat juridique`
   - *Exemples non reconnus comme priorité :* `(a) test`, `(B)->urgent`, `Rappel (A)`.

2. **Règle 2 : La date de création (optionnelle) suit directement la priorité**
   - Format ISO-8601 : `YYYY-MM-DD`.
   - Si la tâche n'a pas de priorité, la date de création apparaît en premier.
   - *Exemples :*
     - `(A) 2026-10-07 Contacter le client`
     - `2026-10-07 Rédiger la documentation`

3. **Règle 3 : Les contextes et projets peuvent apparaître n'importe où dans la description**
   - **Projet** : préfixé par `+` suivi de caractères non blancs (ex. `+RefonteSite`, `+Comptabilite`).
   - **Contexte** : préfixé par `@` suivi de caractères non blancs (ex. `@bureau`, `@telephone`, `@courses`).
   - Une tâche peut comporter zéro, un ou plusieurs projets et contextes.

---

### Règles du format pour les tâches terminées (*Complete Tasks*)

Une tâche terminée est caractérisée par deux éléments :

1. **Règle 1 : Commence par `x ` en minuscule**
   - La lettre `x` minuscule suivie d'un espace au tout début de ligne indique l'achèvement.
   - Le `x` minuscule permet de repousser les tâches faites en bas de liste lors d'un tri alphabétique.
   - *Exemple :* `x 2026-10-07 Nettoyer le serveur`

2. **Règle 2 : La date d'achèvement apparaît immédiatement après le `x `**
   - Format : `x YYYY-MM-DD Description`
   - Si la tâche comportait une date de création, celle-ci est décalée juste après la date d'achèvement :
     - Format : `x YYYY-MM-DD YYYY-MM-DD Description`
     - *Exemple :* `x 2026-10-07 2026-10-01 Livrer la version 1.0 +Projet`
     - Cela permet de mesurer facilement le temps de réalisation (durée = date achèvement - date création).
   - Les clients retirent généralement la priorité d'origine `(A)` lors de la complétion et la déplacent dans un champ `pri:A`.

---

## 2. Spécification des champs spéciaux (*Key:Value tags*)

La spécification officielle définit la règle générale d'extension pour les outils tiers :

> Les développeurs d'outils peuvent définir des règles additionnelles sous la forme `cle:valeur` (ex. `due:2026-10-15`).
> - La clé et la valeur sont composées de caractères non blancs sans deux-points (`:`).
> - Un seul caractère deux-points `:` sépare la clé de la valeur.
> - Les métadonnées peuvent être placées n'importe où après le préfixe de début de ligne.

---

## 3. Les champs spéciaux standards et de facto

Au fil des années, l'écosystème (Todo.txt CLI, Simpletask, Topydo, Sleek, plugins Obsidian) a convergé vers des balises de facto standards :

| Balise | Syntaxe / Exemple | Rôle & Sémantique | Outils / Référence |
| :--- | :--- | :--- | :--- |
| **`due:`** | `due:YYYY-MM-DD` ou `due:ASAP` | Date d'échéance (*deadline*). Déclenche les alertes de retard (*overdue*) et le regroupement temporel. | Standard de facto universel (Sleek, Topydo, Simpletask, CLI) |
| **`t:`** | `t:YYYY-MM-DD` | Date de seuil / activation (*threshold* ou *defer/tickler* en GTD). La tâche est masquée jusqu'à cette date. | Standard GTD (Topydo, Simpletask, addon schedule) |
| **`rec:` / `recur:`** | `rec:1d`, `rec:2w`, `rec:1m`, `rec:1y` ou `rec:+1w` | Périodicité de récurrence (`d` = jour, `b` = ouvré, `w` = semaine, `m` = mois, `y` = an). Préfixe `+` pour récurrence stricte (depuis l'échéance) vs relative (depuis la complétion). | Sleek, Simpletask, Topydo (`rec:`), TodoTxt (`recur:`) |
| **`pri:`** | `pri:A` | Préservation de la priorité d'origine lors de l'archivage ou de la complétion pour restauration ultérieure. | Mentionné dans la spécification officielle Todo.txt |
| **`h:`** | `h:1` | Marqueur de tâche masquée (*hidden*). N'apparaît pas dans la vue principale sans filtre explicite. | Simpletask, Topydo, scripts de filtrage |
| **`id:`** | `id:101` | Identifiant persistant de la tâche, utilisé pour les synchronisations et la hiérarchie. | Addons outline, synchroniseurs |
| **`p:` / `dep:`** | `p:101` ou `dep:101,102` | Dépendance vers une tâche parent ou prérequis (bloquante tant que l'ID n'est pas terminé). | Topydo, addon outline |
| **`note:`** | `note:fichier.txt` | Référence vers un fichier de notes markdown/texte lié à la tâche. | Addon note |
| **`min:`** | `min:45` | Temps de travail cumulé en minutes (chronométrage). | Addon donow |
| **`count:`** | `count:3` | Compteur décrémental d'occurrences restantes. | Addon count |

---

## 4. Écosystème des Addons Todo.txt (*Todo.sh Add-on Directory*)

Dans `todo.txt-cli`, les addons sont des scripts modulaires placés dans `~/.todo.actions.d/` qui enrichissent les commandes de base :

### Gestion du temps et des échéances
* **`due` / `setdue`** : Filtre, liste et met à jour en masse les échéances `due:`.
* **`schedule` / `futureTasks` / `today`** : Filtrage et gestion des dates de seuil `t:` pour ne voir que ce qui est réalisable aujourd'hui.
* **`again` / `dorecur` / `recur` / `ice_recur`** : Gestion automatique des récurrences (recréation de la prochaine occurrence dès que la précédente est marquée `x`).
* **`autopri`** : Augmentation dynamique de la priorité d'une tâche à l'approche de son échéance `due:`.

### Organisation et méthodologie GTD
* **`mit` / `mitf` (*Most Important Tasks*)** : Sélection et focalisation sur 1 à 3 tâches capitales par jour.
* **`outline`** : Arborescence de tâches et décomposition en sous-actions avec `id:`.
* **`hiding` / `hide`** : Masquage contextuel de projets ou de contextes (ex. `@someday`).
* **`projectview` / `lsgp` / `lsgc`** : Affichage multi-colonnes par projet ou par contexte.

### Suivi et productivité
* **`donow`** : Minuteur d'activité qui calcule le temps passé et incrémente `min:XX`.
* **`clock`** : Synchronisation avec le time-tracker GNOME Hamster.
* **`graph` / `xp`** : Rapports visuels d'accomplissement journalier (*Don't break the chain*).
* **`birdseye`** : Vue d'ensemble de la santé et de l'avancement des projets.

### Versioning et synchronisation
* **`sync` / `commit` / `push` / `pull`** : Suivi Git automatique des fichiers `todo.txt` et `done.txt`.
* **`remind` / `book`** : Ponts vers Apple Reminders ou calendriers CalDAV.

---

## 5. Règles déjà établies dans notre implémentation (`todo-tui`)

Le projet `todo-tui` applique d'ores et déjà un ensemble de règles strictes pour les champs spéciaux :

1. **`due:`** :
   - Support des dates ISO-8601 (`due:YYYY-MM-DD`).
   - Support des valeurs textuelles telles que `due:ASAP` (classée en priorité absolue dans l'agenda).
   - Calcul des 4 compartiments d'échéance : `:overdue`, `:today`, `:week`, `:later`.
   - Affichage stylé dans la TUI (jaune gras) et volet de détail.

2. **`t:` (seuil de démarrage)** :
   - Filtrage dans `Query.visible/2` : les tâches non faites avec un seuil futur sont masquées par défaut.
   - Intégration dans la vue agenda (`Ops.agenda/2`).
   - Décalage automatique lors de la récurrence.

3. **`pri:` (sauvegarde de priorité)** :
   - Préservation automatique de la priorité d'origine `(A)`-`(Z)` sous forme de tag `pri:X` lors de la complétion (`complete/2`).
   - Restauration de la priorité d'origine et suppression du tag `pri:X` lors de la réouverture (`uncomplete/1`).

4. **`recur:` (récurrence)** :
   - Parsing d'intervalles `Nu` ou `+Nu` (unités : `d`, `w`, `m`, `y`).
   - Mode relatif (`+Nu`) : calculé à partir de la date du jour `today`.
   - Mode strict (`Nu`) : calculé à partir de l'ancienne date `due:` (avec repli sur `today`).
   - Préservation et report proportionnel du décalage de seuil `t:`.
   - Génération de la nouvelle tâche lors de `Ops.complete/3`.

5. **Architecture TUI & Rendu** :
   - Architecture pure : génération d'un arbre `RenderNode` dans `View` et adaptation à la fois pour le moteur `TermUI` et le backend `ExRatatui`.
   - Rendu adaptatif selon la largeur de terminal (<50, 50-75, >=75 colonnes).
   - Prise en charge du mode sans couleur (`--plain`).
