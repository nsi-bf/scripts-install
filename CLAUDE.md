# Objectif

Un élève dispose d'**une commande** à copier-coller dans un terminal pour
obtenir un environnement de développement complet, puis d'une seconde
(`nsi git`) pour être relié à son dépôt.

Ce sont de jeunes élèves débutants : tout doit être simple et idempotent.

**[`ARCHI.md`](ARCHI.md) fait foi.** En cas de contradiction entre ce fichier,
le code et ARCHI.md, c'est ARCHI.md qui tranche et les autres qui se corrigent.

## Les trois artefacts

| Fichier | Portée | Rôle |
|---|---|---|
| [`setup-windows.ps1`](setup-windows.ps1) | Windows | fabriquer une machine Linux utilisable, puis passer la main |
| [`setup.sh`](setup.sh) | WSL, Linux, macOS | poser `nsi` et lancer `nsi install base` |
| [`nsi`](nsi) | WSL, Linux, macOS | l'outil : composants, git, mise à jour |

Ils vivent dans un dépôt **public** : l'amorçage se fait par `curl` sans aucun
jeton, l'élève n'en a pas encore.

## Points d'entrée

**Windows** (cmd.exe ou PowerShell) :
```
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup-windows.ps1 | iex"
```

**Mac / Linux** :
```
curl -fsSL https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup.sh | bash
```

Servis depuis GitHub raw (branche `main`), sans releases à gérer.

## setup-windows.ps1

Idempotent. Ne connaît **aucun** outil pédagogique : ni `nsi`, ni `uv`, ni gleam.

1. Installe VSCode via `winget` + l'extension `ms-vscode-remote.remote-wsl`
2. Vérifie les fonctionnalités Windows de WSL2 ; s'il en manque, affiche en
   ROUGE de redémarrer et de relancer la commande, puis s'arrête
3. Installe WSL Debian (`wsl --install -d Debian`)
4. Crée l'utilisateur `padawan` / `padawan`, groupe `sudo`
5. Pose un `sudoers.d` NOPASSWD temporaire (l'installation qui suit tourne sans
   terminal, personne ne pourrait taper un mot de passe), installe `curl`,
   appelle `setup.sh` dans WSL, puis révoque le NOPASSWD
6. Définit `padawan` comme utilisateur par défaut (`/etc/wsl.conf` + clé de
   registre `DefaultUid`)
7. Ouvre une console Debian interactive qui lance `nsi git`, puis laisse un
   shell (`exec bash`)

Attend que Windows Update ait fini avant DISM et `wsl --install` : sans ça
l'élève croit le script figé pendant dix minutes.

## setup.sh

Identique sur les trois plateformes, aucune condition à écrire.

- Installe `curl` s'il est absent (seul paquet système qu'il pose)
- Télécharge `nsi` dans `~/.local/bin`
- Lance `nsi install base`
- Indique `nsi git` comme étape suivante

## nsi

Script shell unique, auto-contenu.

- Détecte l'OS (apt / dnf / brew) et WSL
- Idempotent : vérifie avant d'agir
- Installé dans `~/.local/bin/nsi` (`INSTALL_PATH`). Ni son installation ni sa
  mise à jour n'exigent `sudo`. Se réinstalle tout seul s'il est lancé depuis
  un autre chemin.
- `sudo` n'est employé que pour les paquets système sans alternative
  utilisateur raisonnable : `apt`/`dnf`, Erlang, `build-essential`, `gdb`,
  PostgreSQL, les dépôts `gh` et VSCode.
- **Ne s'invoque jamais avec `sudo` en tête** (`nsi install base`, pas
  `sudo nsi install base`). Sur macOS il s'arrête et le dit : Homebrew refuse
  d'être lancé en root et casserait en silence.
- `nsi update` retélécharge le script, remplace `$INSTALL_PATH` et termine
  immédiatement (`exit 0`) — il ne faut pas relire un fichier qu'on remplace.

### VSCode : la frontière

| Plateforme | Qui l'installe |
|---|---|
| WSL | `setup-windows.ps1`, côté Windows |
| Linux / macOS natif | `nsi`, via `install_vscode` |

`install_vscode` commence par `is_wsl && return 0`. C'est le seul endroit qui
porte cette décision.

## Composants

### base
- git
- uv
- graphviz
- gh-cli
- vscode (ignoré sous WSL)

### autres composants (installables individuellement)
- `gleam` — Gleam + Erlang
- `postgresql` — configuration développeur sans sécurité, superuser `dev`/`dev`
- `openjdk` — JDK complet
- `nasm` — assembleur x86
- `rust` — via rustup, dans `/usr/local/rustup` et `/usr/local/cargo`
  (accessible à tous les utilisateurs), binaires symlinkés dans `/usr/local/bin`
- `prolog` — SWI-Prolog (`swipl`)
- `c` — GCC/G++/Make/GDB (`build-essential gdb` sur Debian, `gcc gcc-c++ make
  gdb` sur Fedora, Xcode CLT + `gdb` sur macOS)

## Interface

```
nsi install <composant>
nsi remove <composant>
nsi update
nsi git         # configuration initiale de git et GitHub
nsi push        # commit horodaté + push
nsi pull        # pull
nsi settings    # remet la configuration du projet à la version du modèle
```

## Structure du repo

```
repo/
  setup-windows.ps1   # amorçage Windows
  setup.sh            # amorçage WSL / Linux / macOS
  nsi                 # l'outil
  ARCHI.md            # l'architecture, qui fait foi
  SETUP-ORG.md        # mise en place de l'organisation GitHub, côté prof
  README.md           # mode d'emploi élève
  .gitattributes      # LF pour les scripts shell, CRLF pour .ps1
```

Les fichiers de configuration de l'élève (`settings.json`, `pyproject.toml`,
`.gitignore`…) **ne sont pas ici** : ils vivent dans le dépôt-modèle
`nsi-bf/template-eleves`, source unique.

## Côté prof : l'organisation GitHub

Voir [`SETUP-ORG.md`](SETUP-ORG.md).

L'organisation est `nsi-bf`. **Tout ce qui la peuple est fait par metatest**
(`outils/equipe_github.py`), qui seul connaît la base des élèves : équipes,
dépôts, dépôt-modèle. Ce dépôt-ci ne contient aucun outil d'administration
(`nsi-admin` a été supprimé le 2026-09-11, redondant et divergent).

### Convention de nommage

**Contrat partagé avec metatest, documenté à l'identique des deux côtés** —
metatest l'écrit (`nom_equipe`/`nom_depot` dans `outils/equipe_github.py`),
`nsi git` le relit. Deux dépôts distincts, rien ne les synchronise : une
modification d'un côté est à répercuter à la main de l'autre.

- **Année scolaire** : `AAAA-AAAA+1`, bascule le 1ᵉʳ août. Ex. `2026-2027`.
- **Équipe** : `<classe>_<année>` — ex. `1G3_2026-2027`. Le nom de classe est
  celui de metatest, sans transformation ; les classes reviennent chaque année
  sous le même nom, l'année désambiguïse.
- **Dépôt élève** : `<équipe>-<compte>` — ex. `1G3_2026-2027-Marie-Dupont`.
  Un dépôt neuf par inscription, même pour un élève qui repasse une autre année.
- **Dossier local** : `~/<équipe>`, jamais `~/<pseudo>` — jamais de collision
  avec un ancien clone.
- **Caractères autorisés** : alphanumériques ASCII, `.`, `_`, `-` uniquement,
  validé côté écriture par `nom_depot()`.
- **Désambiguïsation** si plusieurs équipes la même année (ne devrait pas
  arriver) : celle commençant par `T` l'emporte sur celle en `P`.

### `nsi git`

Interdit à root. Demande un seul champ : un token d'accès personnel, portées
`repo` **et** `read:org` (`read:org` sert à retrouver l'équipe ; `repo` seul ne
suffit pas).

Ne demande ni classe ni nom de dépôt : il lit le pseudo (`gh api user`),
calcule l'année scolaire, retrouve l'équipe (`gh api /user/teams`), en déduit
dépôt et dossier selon la convention ci-dessus. Si aucune équipe ou aucun dépôt
n'est trouvé (élève pas encore inscrit, invitations pas acceptées, classe pas
encore mise en place), affiche une erreur et s'arrête sans rien créer.

- `git config user.name` = pseudo GitHub (pas de nom réel demandé).
- `git config user.email` = `<pseudo>@users.noreply.github.com` : l'API `/user`
  ne rend l'email que s'il est public (rare), et lire l'email privé exigerait
  la portée `user:email` en plus.
- `gh auth login --with-token` n'authentifie que `gh`. `gh auth setup-git` est
  appelé juste après pour l'enregistrer comme credential helper — sans ça,
  `nsi push`/`nsi pull`, qui appellent `git` directement, ne le seraient pas.

Clone ensuite le dépôt dans `~/<équipe>`, lance `uv sync`, ouvre VSCode.
**Ne déploie aucun fichier** : ils viennent du modèle dont le dépôt est issu.

### `nsi settings`

Retélécharge les fichiers de configuration depuis `nsi-bf/template-eleves` et
les écrase. Commande explicite, avec avertissement à l'élève : elle réinitialise
`pyproject.toml`, donc ses `uv add`.

### `nsi push` / `nsi pull`

`git add -A && git commit -m "Sauvegarde du <date>" && git push` — sans erreur
si rien n'a changé. Et `git pull`.
