# Architecture

Découpage validé le 2026-09-11. Trois artefacts, trois responsabilités.

## Contrainte fondatrice

L'amorçage se fait par `curl` **sans aucun jeton GitHub** : l'élève n'en a pas
encore, c'est `nsi init` qui le lui fera créer.

→ `setup-windows.ps1`, `setup.sh` et `nsi` doivent vivre dans un dépôt
**public**. Une visibilité « membres de l'organisation » ne suffit pas : elle
exige une authentification que `curl` n'a pas.

## setup-windows.ps1 : Windows uniquement

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

## setup.sh : WSL, Linux, macOS

Rôle unique : installer l'environnement élève sur un Linux quelconque.

- Installe `curl` si absent.
- Télécharge `nsi` dans `~/.local/bin`.
- Lance `nsi install base`.
- Termine en indiquant `nsi init` comme étape suivante.

Identique sur les trois plateformes : aucune condition à écrire.

## nsi : l'outil

Installé dans `~/.local/bin/nsi` (`INSTALL_PATH`). Ni son installation ni sa
mise à jour n'exigent `sudo`.

`sudo` n'est employé que pour les paquets système, sans alternative
utilisateur raisonnable : `apt`/`dnf`/`pacman`, Erlang, `build-essential`,
`gdb`, PostgreSQL, les dépôts `gh` et VS Code.

**Aucune dépendance système qui puisse être évitée.** Le peu de Python dont
`nsi` a besoin, pour réécrire le JSONC de `settings.json` (`nsi ai`,
`nsi toggle-config`), passe par `python_uv`, soit `uv run --no-project python`,
jamais par un `python3` du système : `nsi install base` ne l'installe pas, rien
de ce qu'il pose ne le tire, et sur macOS `/usr/bin/python3` n'est qu'un talon
qui réclame les Command Line Tools. `uv` est déjà là de toute façon, et fournit
l'interpréteur, qu'il télécharge au besoin.

Distributions prises en charge : Debian et dérivées (`apt`), Fedora (`dnf`),
Arch et dérivées comme Manjaro (`pacman`), macOS (`brew`). On ne vise pas
toutes les distributions : un élève qui en a choisi une autre sait chercher.

## Points d'entrée

| Élève | Commande |
|---|---|
| Windows | `irm .../setup-windows.ps1 \| iex` |
| Linux / macOS | `curl -fsSL .../setup.sh \| bash` |

## VS Code : la frontière

| Plateforme | Qui l'installe |
|---|---|
| WSL | `setup-windows.ps1`, côté Windows |
| Arch et dérivées | **l'élève lui-même**, avant |
| autre Linux / macOS natif | `nsi`, via `install_vscode` |

`install_vscode` commence par `is_wsl && return 0`. C'est le seul endroit qui
porte cette décision : si VS Code devait un jour être installé sous WSL côté
Linux, c'est cette ligne qu'il faudrait changer, pas les scripts.

Sur Arch, `exiger_vscode_arch` ouvre `install_base` : si la commande `code`
manque, `nsi` s'arrête et demande à l'élève d'installer VS Code lui-même, en
l'orientant vers une recherche. VS Code et rien d'autre : VSCodium, qui fournit
`codium` et non `code`, n'est pas accepté. On gère déjà plusieurs
distributions, on ne gère pas en plus plusieurs éditeurs.
Le test est fait en tête pour qu'il l'apprenne avant d'avoir attendu le reste.

La contrepartie est que sous WSL, le `code` qu'appelle `nsi init` est celui de
l'installation Windows, atteint par l'interop, et il n'ouvre le dossier Linux
que si l'extension `ms-vscode-remote.remote-wsl` est installée côté Windows.
`setup-windows.ps1` la pose dans ses deux branches pour cette raison.

## IA dans VS Code : ce que `nsi` impose

Le modèle livre `"chat.disableAIFeatures": true` : un dépôt neuf arrive avec
l'IA coupée. `nsi ai` la bascule, dans le `settings.json` du dépôt, et ce choix
appartient à l'élève.

Ce que `nsi ai` ne peut pas faire : connecter VS Code à GitHub. Le jeton de
`nsi init` authentifie `gh`, et `git` à travers lui ; VS Code a sa propre
session OAuth, qu'aucun script ne peut poser. C'est un clic de l'élève, une
fois par poste, et `nsi ai` le lui rappelle à chaque activation.

Les suggestions en ligne, elles, ne lui appartiennent pas : `nsi ai` les
recoupe d'office **dans les deux sens** (`github.copilot.enable` à
`{ "*": false }`, `github.copilot.nextEditSuggestions.enabled` à `false`),
et les remet ainsi même si l'élève les avait changées à la main. Il peut
discuter avec l'IA, il ne peut pas la laisser écrire son code en fantôme dans
l'éditeur. C'est la seule chose que ce dépôt impose en matière d'IA.

## Fichiers de configuration élève

`settings.json`, `extensions.json`, `pyproject.toml`, `.gitignore`,
`.github/copilot-instructions.md` (ajouté le 2026-10-28).

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

`.github/copilot-instructions.md` est dans `TEMPLATE_FICHIERS`, donc
`nsi reset-config` le remet à neuf comme les quatre autres. Il a en plus une
troisième voie, `nsi ai` : à chaque activation de l'IA, les consignes de tuteur
sont reprises du modèle au même chemin. Deux raisons : c'est l'emplacement que
VS Code lit de lui-même, donc le fichier doit être dans le dépôt de l'élève et
pas seulement dans le modèle ; et un dépôt engendré avant son ajout au modèle ne
l'a pas. `nsi ai` ne couvre que l'activation, la désactivation laisse le fichier
en place : il ne sert alors à personne, et c'est `nsi reset-config` qui le
rafraîchit en dehors de ce moment.
