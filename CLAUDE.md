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

### Deux situations, une seule commande

| | Chez l'élève | Au lycée |
|---|---|---|
| Droits | administrateur de sa machine | **pas** administrateur, et ne peut pas l'être |
| VSCode, WSL | à installer | déjà posés par l'image du poste |
| Ce que fait le script | tout | va droit à la Debian |

**On ne demande pas à l'élève où il est** : la machine sait répondre, et un
débutant peut se tromper. Deux sondes, sans élévation et **sans rien exécuter** :

- WSL installé ? `Test-WslInstalle` lit la présence du service **`WSLService`**
  *ou* **`LxssManager`**, sinon celle du paquet Store
  `MicrosoftCorporationII.WindowsSubsystemForLinux`. Les deux noms sont
  nécessaires : il y a deux WSL, et sur une machine à jour c'est `WSLService`
  qui existe et `LxssManager` qui manque (mesuré, WSL 2.7.13.0).
- VSCode ? `code` trouvable dans le PATH, puis dans les trois dossiers
  d'installation connus.

**Ne jamais sonder en appelant `wsl.exe`.** Invoqué alors que WSL n'est pas
installé, il propose de s'installer et le fait au bout d'une trentaine de
secondes, quelle que soit l'option passée : une sonde qui déclenche ce qu'elle
mesure n'est pas une sonde.

`Get-WindowsOptionalFeature -Online` exige l'élévation (« L'opération demandée
nécessite une élévation »), donc il ne s'exécute que dans la branche
administrateur.

**Un marqueur tranche le cas intermédiaire.** Sur une machine neuve, le
premier lancement active les fonctionnalités WSL et demande un redémarrage.
Au lancement suivant, l'état est indiscernable d'un poste de lycée :
`LxssManager` existe, VSCode est installé — la sonde répondrait « rien à
élever », alors que WSL n'a été ni mis à jour ni passé en version 2. Le script
pose donc `HKCU\SOFTWARE\nsi-bf\InstallationWindowsEnCours` juste avant de
demander le redémarrage, le relit dans `Get-BesoinAdmin`, et l'efface quand le
travail côté Windows est fini. Un redémarrage étant obligatoire sur toute
machine neuve, ce n'est pas un cas rare mais le parcours normal.

**Ordre : élévation d'abord, mot d'accueil ensuite.** Dans l'autre sens,
l'élève lit le texte, appuie sur entrée, accepte l'UAC, et retrouve le même
texte et la même attente dans la fenêtre élevée.

Une distribution WSL est enregistrée **par utilisateur**, pas par machine :
même sur un poste du lycée où WSL est là, l'élève n'a pas encore sa Debian.
Sa présence se lit sous `HKCU\...\Lxss` (`Get-DistroKey`), pas avec
`wsl --list --quiet` dont la sortie est en UTF-16.

### Structure

Le script est découpé en fonctions, et son déroulé tient en dix lignes à la
fin du fichier :

```powershell
Show-Accueil
$Wsl  = Get-WslPath
$Code = Get-CodePath
if (Get-BesoinAdmin) { Request-Admin; Install-CoteWindows } else { … }
Install-ExtensionWsl
Install-Debian
New-UtilisateurPadawan
Install-EnvironnementEleve
Set-PadawanParDefaut
Open-ConsoleDebian
```

`$Wsl` et `$Code` sont partagés : affectés au niveau script, relus et réécrits
par les fonctions via `$script:`.

**Branche administrateur** — `Install-CoteWindows` seule, et tout ce qu'elle
appelle : `wsl --shutdown` de remise à zéro (réservé à ce cas, il couperait les
autres fenêtres de l'élève au lycée), `Initialize-Winget`, `Install-VSCode`,
`Enable-FonctionnalitesWsl`, `Update-Wsl`, WSL 2 par défaut, puis
`Clear-Marqueur`.

Ce `wsl --shutdown` est gardé par `Test-WslInstalle`, pas seulement par la
présence du binaire : sinon c'est lui qui déclencherait l'auto-installation de
WSL qu'on cherche à éviter.

- `Initialize-Winget` — si `winget` manque, message ROUGE disant de **ne pas
  insister** et de demander l'assistance du professeur, puis arrêt : les trois
  voies pour l'installer (Store, `Repair-WinGetPackageManager`, `.msixbundle`
  de GitHub) sont hors de portée d'un débutant seul chez lui. Sinon le met à
  jour par lui-même, silencieusement.
- `Install-VSCode` — relit le PATH machine et utilisateur après l'installation,
  celui du processus étant figé à son démarrage.
- `Enable-FonctionnalitesWsl` — si une fonctionnalité manquait, affiche en
  ROUGE de redémarrer et de relancer la commande, puis s'arrête.
- `Update-Wsl` — `wsl --update`, repli `--web-download`. Jamais fatal, et
  silencieux même en échec : le code de sortie d'un `--update` sur un WSL déjà
  à jour n'est pas connu, donc un avertissement conditionnel risquerait de
  s'afficher à chaque installation réussie. Un WSL trop vieux échouera
  franchement à l'installation de Debian.

**Commun aux deux** — root *dans* WSL n'est pas administrateur *de Windows* :
créer un utilisateur Debian, écrire `/etc/wsl.conf` ou poser `DefaultUid` sous
`HKCU` se font avec les droits de l'élève.

- `Install-ExtensionWsl` — pose `ms-vscode-remote.remote-wsl` **dans les deux
  cas** : les extensions VSCode s'installent par utilisateur, dans son profil,
  donc que l'image du lycée porte VSCode ne dit rien de ce que l'élève a dans
  le sien — et sans elle il ne peut pas ouvrir son dossier WSL depuis VSCode,
  c'est-à-dire travailler. Aucun droit requis, idempotente.
- `Install-Debian` — `wsl --install -d Debian` si la clé `Lxss` de
  l'utilisateur ne la contient pas, puis première initialisation en root.
- `New-UtilisateurPadawan` — `padawan` / `padawan`, groupe `sudo`.
- `Install-EnvironnementEleve` — pose le `sudoers.d` NOPASSWD (l'installation
  tourne sans terminal, personne ne pourrait taper un mot de passe), installe
  `curl`, appelle `setup.sh`, et **révoque le NOPASSWD dans un `finally`** :
  il ne doit pas survivre à un échec de `setup.sh`.
- `Set-PadawanParDefaut` — `/etc/wsl.conf` + `DefaultUid`, puis `--terminate`.
- `Open-ConsoleDebian` — console interactive qui lance `nsi git`, puis laisse
  un shell (`exec bash`).

`Wait-WindowsUpdateIdle` est appelé avant DISM et avant `wsl --install` : sans
ça l'élève croit le script figé pendant dix minutes.

### Encodage

Le fichier est en UTF-8 **sans BOM**, et ça ne doit pas changer : `iex` sur une
chaîne qui commence par un BOM échoue. Les accents sont sûrs malgré l'absence
de BOM parce que GitHub raw sert `charset=utf-8` et que `irm` décode en
conséquence — mesuré le 2026-09-11 sous Windows PowerShell 5.1.

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
