# Architecture

Découpage validé le 2026-09-11. Trois artefacts, trois responsabilités.

## Contrainte fondatrice

L'amorçage se fait par `curl` **sans aucun jeton GitHub** : l'élève n'en a pas
encore, c'est `nsi git` qui le lui fera créer.

→ `setup-windows.ps1`, `setup.sh` et `nsi` doivent vivre dans un dépôt
**public**. Une visibilité « membres de l'organisation » ne suffit pas : elle
exige une authentification que `curl` n'a pas.

## setup-windows.ps1 — Windows uniquement

Rôle unique : fabriquer une machine Linux utilisable, puis passer la main.

- Active WSL2, installe Debian, attend qu'elle réponde.
- Crée l'utilisateur `padawan` / `padawan`, groupe `sudo`.
- Installe **VS Code côté Windows** + extension `ms-vscode-remote.remote-wsl`.
- Pose un `sudoers.d` NOPASSWD temporaire, le révoque après.
- Appelle `setup.sh` dans WSL.
- Définit `padawan` comme utilisateur par défaut (`wsl.conf` + registre).

Ne connaît **aucun** outil pédagogique : ni `nsi`, ni `uv`, ni gleam.

## setup.sh — WSL, Linux, macOS

Rôle unique : installer l'environnement élève sur un Linux quelconque.

- Installe `curl` si absent.
- Télécharge `nsi` dans `~/.local/bin`.
- Lance `nsi install base`.
- Termine en indiquant `nsi git` comme étape suivante.

Identique sur les trois plateformes : aucune condition à écrire.

## nsi — l'outil

Installé dans `~/.local/bin/nsi` (`INSTALL_PATH`). Ni son installation ni sa
mise à jour n'exigent `sudo`.

`sudo` n'est employé que pour les paquets système, sans alternative
utilisateur raisonnable : `apt`/`dnf`, Erlang, `build-essential`, `gdb`,
PostgreSQL, les dépôts `gh` et VS Code.

## Points d'entrée

| Élève | Commande |
|---|---|
| Windows | `irm .../setup-windows.ps1 \| iex` |
| Linux / macOS | `curl -fsSL .../setup.sh \| bash` |

## VS Code : la frontière

| Plateforme | Qui l'installe |
|---|---|
| WSL | `setup-windows.ps1`, côté Windows |
| Linux / macOS natif | `nsi`, via `install_vscode` |

`install_vscode` commence par `is_wsl && return 0`. C'est le seul endroit qui
porte cette décision : si VS Code devait un jour être installé sous WSL côté
Linux, c'est cette ligne qu'il faudrait changer, pas les scripts.

## Fichiers de configuration élève

`settings.json`, `extensions.json`, `tasks.json`, `pyproject.toml`,
`.gitignore`.

Aujourd'hui récupérés par `curl` dans `cmd_git` et `cmd_settings`, ce qui
**écrase** le travail de l'élève à chaque appel.

Piste retenue : les déplacer dans le template de dépôt de l'organisation
`nsi-bf`, et créer les dépôts élèves à partir de ce template.

Contrepartie assumée : un template est un instantané, il ne propage rien aux
dépôts déjà créés. On échange « corriger tout le monde d'un coup » contre
« ne jamais écraser le travail d'un élève ». `nsi settings` peut rester comme
commande explicite pour les cas où la propagation est voulue.
