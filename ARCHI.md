# Architecture

Découpage validé le 2026-09-11. Trois artefacts, trois responsabilités.

## Contrainte fondatrice

L'amorçage se fait par `curl` **sans aucun jeton GitHub** : l'élève n'en a pas
encore, c'est `nsi init` qui le lui fera créer.

→ `setup-windows.ps1`, `setup.sh` et `nsi` doivent vivre dans un dépôt
**public**. Une visibilité « membres de l'organisation » ne suffit pas : elle
exige une authentification que `curl` n'a pas.

## setup-windows.ps1, Windows uniquement

Rôle unique : fabriquer une machine Linux utilisable, puis passer la main.

- Active WSL2, installe Debian, attend qu'elle réponde.
- Crée l'utilisateur `padawan` / `padawan`, groupe `sudo`.
- Installe **VS Code côté Windows** + extension `ms-vscode-remote.remote-wsl`.
- Pose un `sudoers.d` NOPASSWD temporaire, le révoque après.
- Appelle `setup.sh` dans WSL.
- Définit `padawan` comme utilisateur par défaut (`wsl.conf` + registre).
- Ouvre une console Debian qui enchaîne sur `nsi init`, puis laisse un shell.

N'**installe** aucun outil pédagogique : ni `nsi`, ni `uv`, ni gleam. Tout ce
qui s'installe côté Linux passe par `setup.sh`.

La seule exception est la dernière ligne, qui nomme `nsi init` pour enchaîner.
C'est assumé : le message de `setup.sh` a défilé dans la fenêtre PowerShell, et
la console qui s'ouvre est un shell neuf. Sans cette ligne l'élève se retrouve
devant un prompt nu, sans rien lui dire quoi taper. Une commande à ne pas
saisir vaut mieux qu'une frontière pure : la règle porte sur qui installe quoi,
pas sur qui prononce un nom.

## setup.sh, WSL, Linux, macOS

Rôle unique : installer l'environnement élève sur un Linux quelconque.

- Installe `curl` si absent.
- Télécharge `nsi` dans `~/.local/bin`.
- Lance `nsi install base`.
- Termine en indiquant `nsi init` comme étape suivante.

Identique sur les trois plateformes : aucune condition à écrire.

## nsi, l'outil

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

La contrepartie est que sous WSL, le `code` qu'appelle `nsi init` est celui de
l'installation Windows, atteint par l'interop, et il n'ouvre le dossier Linux
que si l'extension `ms-vscode-remote.remote-wsl` est installée côté Windows.
`setup-windows.ps1` la pose dans ses deux branches pour cette raison.

## Fichiers de configuration élève

`settings.json`, `extensions.json`, `pyproject.toml`, `.gitignore`.

Pas de `tasks.json` : il portait un `nsi pull` automatique à l'ouverture du
dépôt. Un geste que l'élève n'a pas demandé, qu'il ne voit pas passer et qu'il
ne saurait pas défaire, `nsi pull` est une commande qu'il tape.

Ils ne sont plus dans ce dépôt (fait le 2026-09-11). Ils vivent dans le
dépôt-modèle `nsi-bf/template-eleves`, dont chaque dépôt d'élève est engendré :
c'est la seule source.

`nsi init` ne déploie donc plus rien, il clone, `uv sync`, ouvre VS Code. Il
n'écrase plus le travail de l'élève à chaque appel, ce qu'il faisait quand il
tirait ces fichiers par `curl`.

Contrepartie assumée : un modèle est un instantané, GitHub ne propage rien aux
dépôts déjà créés. On échange « corriger tout le monde d'un coup » contre
« ne jamais écraser le travail d'un élève ». Deux commandes explicites le
rattrapent quand la propagation est voulue : `nsi reset-config` côté élève, et
`equipe_github.py --rafraichir` côté prof, qui réécrit les fichiers tenus dans
tous les dépôts d'une classe.
