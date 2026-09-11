# Objectif

Un élève dispose de deux commandes à copier-coller dans un terminal pour accéder à un environnement de développement complet.

Ce sont de jeunes élèves débutants, il faut que ça soit facile d'utilisation et idempotent.

## Commandes de bootstrap

**Windows** (cmd.exe ou PowerShell) :
```
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup.ps1 | iex"
```

**Mac / Linux** :
```
curl -fsSL https://raw.githubusercontent.com/nsi-bf/scripts-install/main/nsi | bash -s -- install base
```

Les scripts sont servis depuis GitHub raw (branche main), sans releases à gérer.

## OS

### Windows

`setup.ps1` est un script PowerShell idempotent qui :

1. Installe VSCode via `winget` + extension `ms-vscode-remote.remote-wsl`
2. Vérifie que WSL2 est actif ; si des fonctionnalités manquent, affiche un message en ROUGE demandant de redémarrer et de relancer la commande, puis s'arrête
3. Installe WSL Debian : `wsl --install -d Debian`
4. Configure l'utilisateur `padawan` / `padawan` en ligne de commande
5. Accorde temporairement le sudo sans mot de passe (nécessaire pour un appel non interactif, sans terminal pour taper un mot de passe), puis installe les outils via `nsi install base`, et révoque le sudo sans mot de passe
6. Définit `padawan` comme utilisateur par défaut (via `/etc/wsl.conf` + clé de registre `DefaultUid`)
7. Ouvre une console Debian interactive qui lance automatiquement `nsi git`, puis laisse un shell interactif (`exec bash`) une fois la configuration terminée

### Linux / Mac

`nsi` est un script shell unique auto-contenu qui :

- Détecte l'OS (apt / dnf / brew)
- Détecte WSL
- Est idempotent (vérifie avant d'agir)
- Gère install et remove par composant
- Se met à jour via `nsi update` (curl + tee + exit 0 immédiat pour éviter la relecture du fichier remplacé)
- **Ne s'invoque jamais avec `sudo` en tête** (`nsi install base`, pas `sudo nsi install base`) : chaque opération qui a besoin de root l'appelle elle-même en interne (`sudo apt-get`/`dnf`/écritures sous `/usr/local`…), jamais les chemins Homebrew, qui refusent d'être lancés en root. Sur macOS, `nsi` s'arrête et le dit si on le lance quand même avec `sudo` — sinon Homebrew casserait en silence.

Il est téléchargé dans `/usr/local/bin` et rendu exécutable.

## Composants

### base
- vscode (ignoré si WSL — VSCode est déjà installé côté Windows)
- git
- uv (installé dans `/usr/local/bin` via `UV_INSTALL_DIR`)
- graphviz
- gh-cli

### autres composants (installables individuellement)
- `gleam` — Gleam + Erlang
- `postgresql` — configuration développeur sans sécurité, avec superuser `dev`/`dev`
- `openjdk` — JDK complet
- `nasm` — assembleur x86
- `rust` — Rust via rustup, installé dans `/usr/local/rustup` et `/usr/local/cargo` (accessible à tous les utilisateurs), binaires symlinkés dans `/usr/local/bin`
- `prolog` — SWI-Prolog (`swipl`)
- `c` — GCC/G++/Make/GDB (`build-essential gdb` sur Debian, `gcc gcc-c++ make gdb` sur Fedora, Xcode CLT + `gdb` sur macOS)

## Interface nsi

```
nsi install base
nsi remove base
nsi install gleam
nsi remove gleam
# etc.
nsi update
```

`nsi update` retélécharge le script depuis GitHub raw, remplace `/usr/local/bin/nsi` et termine immédiatement (`exit 0`).

## Structure du repo

```
repo/
  setup.ps1         # bootstrap Windows
  nsi               # script shell principal (Linux / Mac / WSL)
  settings.json     # paramètres VSCode déployés dans .vscode/ du dépôt élève
  extensions.json   # recommandations d'extensions VSCode
  tasks.json        # tâche VSCode : nsi pull automatique à l'ouverture
  pyproject.toml    # projet Python uv déployé dans le dépôt élève
  .gitignore        # gitignore Python/Gleam/Rust/Java déployé dans le dépôt élève
  .gitattributes    # force LF pour les scripts shell, CRLF pour .ps1
```

## Gestion de git

```
nsi git         # configuration initiale
nsi push        # commit horodaté + push
nsi pull        # pull
nsi settings    # redéploie settings.json / extensions.json / tasks.json / pyproject.toml / .gitignore
```

### Convention de nommage GitHub (organisation `nsi-bf`)

**Contrat partagé avec metatest, documenté à l'identique des deux côtés** — metatest
l'écrit (`outils/equipe_github.py`, fonctions `nom_equipe`/`nom_depot`), `nsi git`
le relit ci-dessous. Ce sont deux dépôts distincts : rien ne les synchronise
automatiquement, une modification d'un côté doit être répercutée manuellement de
l'autre.

- **Année scolaire** : `AAAA-AAAA+1`, bascule le 1ᵉʳ août (pas le 1ᵉʳ janvier).
  Ex. `2026-2027`.
- **Équipe (team GitHub)** : `<classe>_<année>` — ex. `TNSINFGR_2_2026-2027`.
  `<classe>` est le nom de classe tel qu'il est dans metatest, sans
  transformation. Les classes reviennent chaque année sous le même nom ;
  l'année désambiguïse.
- **Dépôt élève** : `<équipe>-<pseudo_github>` — ex.
  `TNSINFGR_2_2026-2027-Marie-Dupont`. Garantit un dépôt neuf par inscription,
  y compris pour un élève qui repasse par le système une autre année.
- **Dossier local (poste élève)** : `~/<équipe>` — ex.
  `~/TNSINFGR_2_2026-2027`, jamais `~/<pseudo>`. Distinct d'une année sur
  l'autre pour un même élève : jamais de collision avec un ancien clone.
- **Organisation** : `nsi-bf`.
- **Caractères autorisés** dans classe et pseudo (donc dans équipe et dépôt) :
  alphanumériques ASCII, `.`, `_`, `-` uniquement — validé côté écriture par
  `nom_depot()` dans `equipe_github.py`.
- **Désambiguïsation** si un élève appartient à plusieurs équipes de l'année en
  cours (ne devrait pas arriver en temps normal — une équipe par élève et par
  année) : celle commençant par `T` (terminale) l'emporte sur celle en `P`
  (première).

### `nsi git`

Interdit à root. Configure git et authentifie GitHub. Demande interactivement un seul champ : un token d'accès personnel (portées `repo` et `read:org`, créé sur https://github.com/settings/tokens). `read:org` est nécessaire pour retrouver l'équipe de l'élève (ci-dessus), `repo` seul ne suffit plus.

Les dépôts élèves vivent dans l'organisation `nsi-bf`, gérée côté prof depuis **metatest** (`outils/equipe_github.py`), pas depuis `nsi-admin`. `nsi git` ne demande ni classe ni nom de dépôt : une fois authentifié, il récupère le pseudo via `gh api user --jq .login`, calcule l'année scolaire en cours, retrouve l'équipe correspondante via `gh api /user/teams`, et en déduit dépôt et dossier local selon la [convention de nommage](#convention-de-nommage-github-organisation-nsi-bf) ci-dessus. Si aucune équipe ou aucun dépôt n'est trouvé (élève pas encore inscrit, invitations pas acceptées, classe pas encore mise en place côté metatest), affiche un message d'erreur et s'arrête sans rien créer.

`git config user.name` est mis au pseudo GitHub (pas de nom réel demandé) ; `git config user.email` est dérivé en `<pseudo>@users.noreply.github.com` (l'adresse "no-reply" standard de GitHub), l'API `/user` ne renvoyant l'email public que si l'élève l'a explicitement rendu public sur son profil (rare), et lire l'email privé nécessiterait le scope `user:email` en plus.

`gh auth login --with-token` authentifie uniquement le CLI `gh` (utilisé pour `gh repo view`/`gh repo clone`) ; il ne configure pas `git` lui-même. `gh auth setup-git` est donc appelé juste après pour enregistrer `gh` comme credential helper git — sans ça, `nsi push`/`nsi pull` (qui utilisent `git` directement) ne seraient pas authentifiés.

Déploie ensuite `.vscode/settings.json`, `.vscode/extensions.json`, `.vscode/tasks.json`, `pyproject.toml`, `.gitignore`, lance `uv sync`, puis ouvre VSCode dans le dossier.

### `nsi push`

Équivalent de `git add -A && git commit -m "Sauvegarde du <date>" && git push`. Ne produit pas d'erreur si rien n'a changé.

### `nsi pull`

Équivalent de `git pull`.

## Organisation GitHub (côté prof)

Les dépôts élèves ne sont pas des dépôts personnels : ils vivent dans l'organisation GitHub **`mmarchand-teacher`**, ce qui garantit un accès prof permanent (owner de l'org) sans dépendre d'une invitation par élève.

- **Dépôt template** : `mmarchand-teacher/template-eleve`, marqué "Template repository" dans ses Settings. Contient la même base que celle déployée par `nsi git`/`nsi settings` (README, pyproject.toml, .gitignore, .vscode/).
- **Team par classe** (ex. `Classe-1B`) : sert uniquement de *roster* — invitation groupée des élèves dans l'organisation et regroupement visuel. **Aucun dépôt n'y est jamais attaché**, pour que les élèves d'une même classe n'aient jamais accès aux dépôts des autres.
- **Accès aux dépôts** : chaque élève est ajouté individuellement comme collaborateur en écriture (`push`) sur son propre dépôt uniquement.

Ce modèle implique deux invitations à accepter côté élève (organisation via la team, puis dépôt individuel) avant que `nsi git` fonctionne.

### `nsi-admin`

Script bash, usage local uniquement par le prof (jamais déployé/auto-mis à jour comme `nsi`). Authentification préalable requise : `gh auth login` en tant que owner de l'organisation.

```
./nsi-admin <fichier.csv> <nom-de-classe>
```

CSV sans en-tête, une ligne par élève : `nom,pseudo_github`.

Pour chaque élève, de façon idempotente : invite dans la team roster de la classe, crée son dépôt depuis `template-eleve` s'il n'existe pas, l'ajoute comme collaborateur en écriture sur ce seul dépôt.

## Paramètres VSCode déployés (`settings.json`)

- `files.autoSave: afterDelay` (1 s) — sauvegarde automatique
- `git.autofetch: true` — synchronisation automatique avec le remote
- `files.exclude` — masque `.vscode/`, `pyproject.toml`, `.gitignore` dans l'Explorer
- Désactivation de Copilot, télémétrie, suggestions IA

## Extensions VSCode

- **Installée automatiquement** (setup.ps1) : `ms-vscode-remote.remote-wsl`
- **Recommandées** (extensions.json, VSCode propose à l'ouverture du dépôt) :
  `tomoki1207.pdf`, `ms-python.python`, `ms-vscode.test-adapter-converter`,
  `hbenl.vscode-test-explorer`, `iterteam.dependi`, `aaron-bond.better-comments`,
  `tamasfe.even-better-toml`, `sanaajani.taskrunnercode`
