# Objectif

Un élève dispose d'**une commande** à copier-coller dans un terminal pour
obtenir un environnement de développement complet, puis d'une seconde
(`nsi init`) pour être relié à son dépôt.

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

**Windows**, dans **PowerShell en tant qu'administrateur** (pas `cmd`) :
```
irm https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup-windows.ps1 -OutFile "$env:TEMP\nsi-setup.ps1"; Set-ExecutionPolicy Bypass -Scope Process -Force; & "$env:TEMP\nsi-setup.ps1"
```

**Le script est écrit sur le disque puis exécuté**, au lieu d'être passé à
`iex`. Exécuter en mémoire du code téléchargé est le motif des chargeurs de
logiciels malveillants, donc ce que l'AMSI surveille en premier ; un fichier
posé puis lancé est analysé comme n'importe quel fichier. En prime, les erreurs
portent un vrai numéro de ligne, et `Request-Admin` relance ce fichier au lieu
de retélécharger.

`Set-ExecutionPolicy -Scope Process` est indispensable et n'exige pas
l'administrateur : la politique `LocalMachine` est `Undefined` sur un Windows
client, donc `Restricted` en pratique, et un `.ps1` ne s'exécuterait pas.

**Mac / Linux** :
```
curl -fsSL https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup.sh | bash
```

Servis depuis GitHub raw (branche `main`), sans releases à gérer.

**Le script n'élève pas lui-même.** `Start-Process -Verb RunAs` échoue sans
la moindre invite, sur un « Accès refusé » que rien n'explique, dès que la
stratégie du poste refuse les élévations (`ConsentPromptBehaviorUser = 0`, ou
compte standard) ; constaté sur un poste de test le 2026-09-11. Et quand elle
réussit, elle ouvre une seconde fenêtre, avec son propre journal et sa propre
sortie à suivre. Quand il manque quelque chose qui exige l'administrateur,
`Stop-DemanderAdmin` affiche le diagnostic et explique comment rouvrir
PowerShell en administrateur. Une étape de plus, mais qui se voit, se comprend
et se recommence.

Au lycée, l'élève ne peut pas être administrateur, et n'en a pas besoin : VSCode
et WSL y sont déjà. Le script ne réclame donc les droits que s'il lui manque
vraiment quelque chose.

**PowerShell et pas `cmd`** : depuis `cmd`, le détecteur de menaces de Windows
refuse la commande (« accès refusé », constaté sur un poste de test le
2026-09-11). `irm … | iex` exécute du code téléchargé en mémoire, sans jamais
l'écrire sur disque : c'est le motif des chargeurs de logiciels malveillants,
donc ce que l'AMSI et les règles ASR surveillent en premier. Le processus
parent entre dans l'heuristique, d'où la différence entre les deux shells.

Si le blocage se produit aussi depuis PowerShell sur d'autres postes, la piste
est d'écrire le script sur disque avant de l'exécuter plutôt que de le passer à
`iex` : un fichier posé puis lancé sort de ces heuristiques. Non testé.

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
`LxssManager` existe, VSCode est installé, la sonde répondrait « rien à
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

**Branche administrateur**, `Install-CoteWindows` seule, et tout ce qu'elle
appelle : `wsl --shutdown` de remise à zéro (réservé à ce cas, il couperait les
autres fenêtres de l'élève au lycée), `Initialize-Winget`, `Install-VSCode`,
`Enable-FonctionnalitesWsl`, `Update-Wsl`, WSL 2 par défaut, puis
`Clear-Marqueur`.

Ce `wsl --shutdown` est gardé par `Test-WslInstalle`, pas seulement par la
présence du binaire : sinon c'est lui qui déclencherait l'auto-installation de
WSL qu'on cherche à éviter.

- `Initialize-Winget`, si `winget` manque, message ROUGE disant de **ne pas
  insister** et de demander l'assistance du professeur, puis arrêt : les trois
  voies pour l'installer (Store, `Repair-WinGetPackageManager`, `.msixbundle`
  de GitHub) sont hors de portée d'un débutant seul chez lui. Sinon le met à
  jour par lui-même, silencieusement.
- `Install-VSCode`, relit le PATH machine et utilisateur après l'installation,
  celui du processus étant figé à son démarrage.
- `Enable-FonctionnalitesWsl`, si une fonctionnalité manquait, affiche en
  ROUGE de redémarrer et de relancer la commande, puis s'arrête.
- `Update-Wsl`, `wsl --update`, repli `--web-download`. Jamais fatal, et
  silencieux même en échec : le code de sortie d'un `--update` sur un WSL déjà
  à jour n'est pas connu, donc un avertissement conditionnel risquerait de
  s'afficher à chaque installation réussie. Un WSL trop vieux échouera
  franchement à l'installation de Debian.

**Commun aux deux**, root *dans* WSL n'est pas administrateur *de Windows* :
créer un utilisateur Debian, écrire `/etc/wsl.conf` ou poser `DefaultUid` sous
`HKCU` se font avec les droits de l'élève.

- `Install-ExtensionWsl`, pose `ms-vscode-remote.remote-wsl` **dans les deux
  cas**, y compris au lycée. Les extensions VSCode s'installent par
  utilisateur, dans son profil : que l'image du poste porte VSCode ne dit rien
  de ce que l'élève a dans le sien. Aucun droit requis, idempotente.

  **Ce n'est pas un confort, c'est ce qui fait que VSCode s'ouvre à la fin de
  l'installation.** `nsi init` termine par `code "$dossier"`. Sous WSL, ce
  `code` est le script livré par l'installation *Windows* de VSCode, atteint
  par l'interop. Ce script détecte WSL via `$WSL_DISTRO_NAME`, puis cherche
  l'extension par `--locate-extension ms-vscode-remote.remote-wsl` : s'il la
  trouve, il délègue à `wslCode.sh`, qui installe le serveur VSCode dans la
  distribution et ouvre une fenêtre Remote-WSL sur le chemin Linux. **Sinon il
  retombe sur sa branche finale et passe `/home/padawan/…` au VSCode Windows,
  qui ne sait pas l'ouvrir.** Retirer cette ligne casse la dernière étape de
  l'installation, sans rien dire.

  (`~/.vscode-server/bin/…/remote-cli/code` masque le script Windows quand il
  existe, mais il n'apparaît qu'après une première connexion Remote-WSL : sur
  une Debian neuve, c'est bien le script Windows qui opère.)
- `Install-Debian`, `wsl --install -d Debian` si la clé `Lxss` de
  l'utilisateur ne la contient pas, puis première initialisation en root.
- `New-UtilisateurPadawan`, `padawan` / `padawan`, groupe `sudo`.
- `Install-EnvironnementEleve`, pose le `sudoers.d` NOPASSWD (l'installation
  tourne sans terminal, personne ne pourrait taper un mot de passe), installe
  `curl`, appelle `setup.sh`, et **révoque le NOPASSWD dans un `finally`** :
  il ne doit pas survivre à un échec de `setup.sh`.
- `Set-PadawanParDefaut`, `/etc/wsl.conf` + `DefaultUid`, puis `--terminate`.
- `Open-ConsoleDebian` : console interactive qui ouvre VSCode par
  `code "$(nsi dir)"` puis laisse un shell (`exec bash -l`). Le `$` est échappé
  en `` `$ `` pour que PowerShell le laisse à bash. **`nsi init` n'y est lancé
  que s'il reste à faire** (`nsi dir >/dev/null || nsi init`) : `setup.sh` l'a
  peut-être déjà fait, car lancé par `wsl.exe` depuis une console PowerShell il
  trouve `/dev/tty` ouvrable même avec `stdin` branché sur le tuyau de `curl`.
  Sans cette garde, l'élève se voyait redemander son jeton une seconde fois,
  juste après l'ouverture de VSCode.

`Wait-WindowsUpdateIdle` est appelé avant DISM et avant `wsl --install` : une
opération de maintenance en cours verrouille les fichiers dont ils ont besoin.

Il ne regarde que le processus **`TiWorker`**, jamais le service
`TrustedInstaller`. Ce service est démarré par n'importe quelle opération de
maintenance, **y compris les appels à `Get-WindowsOptionalFeature` de ce
script**, et reste ensuite actif une dizaine de minutes sans rien faire. S'y
fier faisait attendre pour rien après un redémarrage, en affirmant à l'élève
qu'une mise à jour était en cours alors que Windows Update le disait à jour.

L'attente est bornée à 180 s, après quoi on continue : si les fichiers sont
vraiment verrouillés, l'étape suivante échouera en le disant, ce qui vaut mieux
qu'une attente sans fin devant un écran muet.

### Encodage

Le fichier est en UTF-8 **sans BOM**, et ça ne doit pas changer : `iex` sur une
chaîne qui commence par un BOM échoue. Les accents sont sûrs malgré l'absence
de BOM parce que GitHub raw sert `charset=utf-8` et que `irm` décode en
conséquence, mesuré le 2026-09-11 sous Windows PowerShell 5.1.

## setup.sh

Identique sur les trois plateformes, aucune condition de système à écrire.

- Refuse de tourner en **root** : `curl … | sudo bash` poserait `nsi` dans
  `/root/.local/bin`, invisible pour l'élève, et casserait Homebrew sur macOS.
- Dit ce qui va se passer : rester connecté à Internet, mot de passe possible
  pour les paquets système. **Sans jamais attendre de saisie**, il est aussi
  appelé par `setup-windows.ps1` via `wsl -- bash -c "curl … | bash"`, sans
  terminal : un `read` bloquerait.
- Installe `curl` s'il est absent (seul paquet système qu'il pose).
- Télécharge `nsi` dans `~/.local/bin`, par renommage atomique.
- **`assurer_path`** : garantit qu'un shell de connexion trouvera `nsi`.
  Sur Debian, `~/.profile` ajoute `~/.local/bin` *si le dossier existe*, et il
  vient d'être créé, rien à faire. Sur **macOS**, le shell par défaut est zsh,
  qui ne lit pas `~/.profile` du tout : sans cette fonction, `nsi` ne serait
  jamais dans le PATH et le `nsi init` annoncé échouerait.
  - La sonde tourne sous `env -i` : sinon le shell de connexion hérite du PATH
    courant et répond « c'est bon » alors qu'un terminal neuf ne trouvera rien.
  - Écrit dans `~/.zprofile` sous zsh ; sinon `~/.bash_profile`, `~/.bash_login`
    ou `~/.profile`, dans cet ordre, bash lit `~/.bash_profile` **à la place**
    de `~/.profile` quand il existe.
  - N'écrit rien si un shell de connexion résout déjà `nsi`, ni si le fichier
    mentionne déjà `.local/bin`.
- Lance `nsi install base`, par chemin absolu : `~/.local/bin` n'est pas encore
  dans le PATH de ce shell-ci.
- Enchaîne sur **`nsi init`** puis ouvre VSCode sur `nsi dir`, quand un
  terminal répond, en lisant depuis
  `/dev/tty`. Deux obstacles l'imposent : sous `curl … | bash` stdin est le
  tuyau de curl, et il n'y a pas toujours de terminal de contrôle. Le test est
  `(exec </dev/tty)`, pas `[ -e /dev/tty ]` : le fichier existe même quand
  aucun terminal n'y répond. Sans terminal, le cas de l'appel depuis
  `setup-windows.ps1`, il ne tente rien et indique `nsi init` comme étape
  suivante : c'est la console ouverte par `Open-ConsoleDebian` qui s'en charge,
  et c'est là que l'élève peut taper.

## nsi

Script shell unique, auto-contenu.

- Détecte l'OS (apt / dnf / brew) et WSL
- Idempotent : vérifie avant d'agir
- Installé dans `~/.local/bin/nsi` (`INSTALL_PATH`). Ni son installation ni sa
  mise à jour n'exigent `sudo`. Se réinstalle tout seul s'il est lancé depuis
  un autre chemin.
- **Met `~/.local/bin` dans son propre PATH dès le départ.** C'est là qu'il
  installe `uv` et lui-même, mais un shell ordinaire ne l'a pas : `wsl -- bash
  -c` et le terminal de VSCode donnent `/usr/local/bin:/usr/bin:/bin:/sbin` et
  rien d'autre, seul un shell de connexion lit `~/.profile`. `uv sync`
  échouait alors sur « uv: command not found » alors qu'`uv` était installé.
- `install_uv` impose `UV_INSTALL_DIR="$HOME/.local/bin"` : l'installeur essaie
  sinon `$XDG_BIN_HOME`, puis `$XDG_DATA_HOME/../bin`, et `uv` finirait ailleurs
  que là où `nsi` le cherche.
- `exiger_uv` précède chaque `uv sync` : « uv: command not found » ne dit pas
  quoi faire, « relance `nsi install base` » si.
- `sudo` n'est employé que pour les paquets système sans alternative
  utilisateur raisonnable : `apt`/`dnf`, Erlang, `build-essential`, `gdb`,
  PostgreSQL, les dépôts `gh` et VSCode.
- **Ne s'invoque jamais avec `sudo` en tête** (`nsi install base`, pas
  `sudo nsi install base`). Sur macOS il s'arrête et le dit : Homebrew refuse
  d'être lancé en root et casserait en silence.
- `nsi update` retélécharge le script, remplace `$INSTALL_PATH` et termine
  immédiatement (`exit 0`), il ne faut pas relire un fichier qu'on remplace.

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
- `gleam`, Gleam + Erlang
- `postgresql`, configuration développeur sans sécurité, superuser `dev`/`dev`
- `openjdk`, JDK complet
- `nasm`, assembleur x86
- `rust`, via rustup, dans `/usr/local/rustup` et `/usr/local/cargo`
  (accessible à tous les utilisateurs), binaires symlinkés dans `/usr/local/bin`
- `prolog`, SWI-Prolog (`swipl`)
- `c`, GCC/G++/Make/GDB (`build-essential gdb` sur Debian, `gcc gcc-c++ make
  gdb` sur Fedora, Xcode CLT + `gdb` sur macOS)

## Interface

```
nsi install <composant>
nsi remove <composant>
nsi update
nsi init          # première mise en route : GitHub, dépôt, VSCode
nsi push          # commit horodaté + push
nsi pull          # pull
nsi dir           # imprime le dossier de cours, pour `code "$(nsi dir)"`
nsi reset-config  # remet la configuration du projet à celle du modèle
nsi toggle-config # bascule l'affichage des fichiers de config dans VSCode
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

**Contrat partagé avec metatest, documenté à l'identique des deux côtés** -
metatest l'écrit (`nom_equipe`/`nom_depot` dans `outils/equipe_github.py`),
`nsi init` le relit. Deux dépôts distincts, rien ne les synchronise : une
modification d'un côté est à répercuter à la main de l'autre.

- **Année scolaire** : `AAAA-AAAA+1`, bascule le 1ᵉʳ août. Ex. `2026-2027`.
- **Équipe** : `<classe>_<année>`, ex. `1G3_2026-2027`. Le nom de classe est
  celui de metatest, sans transformation ; les classes reviennent chaque année
  sous le même nom, l'année désambiguïse.
- **Dépôt élève** : `<équipe>-<compte>`, ex. `1G3_2026-2027-Marie-Dupont`.
  Un dépôt neuf par inscription, même pour un élève qui repasse une autre année.
- **Dossier local** : `~/<équipe>`, jamais `~/<pseudo>`, jamais de collision
  avec un ancien clone.
- **Caractères autorisés** : alphanumériques ASCII, `.`, `_`, `-` uniquement,
  validé côté écriture par `nom_depot()`.
- **Désambiguïsation** si plusieurs équipes la même année (ne devrait pas
  arriver) : celle commençant par `T` l'emporte sur celle en `P`.

### `nsi init`

Interdit à root. Demande un seul champ : un token d'accès personnel, portées
**`repo`**, **`read:org`** et **`gist`**.

Ces trois-là ne viennent pas de nos appels, qui n'ont besoin que de `repo`,
mais de **`gh auth login --with-token`**, dont l'aide dit : « The minimum
required scopes for the token are: `repo`, `read:org`, and `gist`. » Un jeton
sans `read:org` est refusé par `gh` sur « missing required scope read:org »,
constaté le 2026-09-11. Ne pas les retirer de la consigne en croyant qu'elles
ne servent plus depuis l'abandon de `/user/teams`.

Ne demande ni classe ni nom de dépôt. Il lit le pseudo (`gh api user`), liste
les dépôts auxquels l'élève a accès (`gh api /user/repos`), garde ceux qui
suivent la convention `<classe>_<AAAA-AAAA>-<pseudo>` dans `nsi-bf`, et prend
**le plus récent** par date de création. L'équipe s'en déduit en retirant le
suffixe `-<pseudo>`, et donne le nom du dossier local. Si rien ne correspond
(élève pas encore inscrit, invitations pas acceptées, classe pas encore mise en
place), affiche une erreur et s'arrête sans rien créer.

**Pourquoi pas l'année scolaire.** La version précédente calculait l'année en
cours, avec bascule au 1ᵉʳ août, et cherchait une équipe finissant par
`_<année>` via `/user/teams`. Trois défauts : échec net si la classe était
créée en avance ou en retard sur ce calendrier, noms d'équipe non triables (une
vieille `Term2425` ne finit même pas par une année), et la portée `read:org`
imposée au jeton pour nos propres besoins. La date de création des dépôts,
elle, tranche sans convention supplémentaire. `read:org` reste néanmoins à
cocher, `gh` l'exigeant pour lui-même (voir ci-dessus).

**Le filtrage se fait en shell, pas en jq.** `gh api --jq` **n'accepte pas
`--arg`** (aucun dans `gh api --help`), donc on ne peut pas lui passer
`$pseudo` ; et `jq` n'est pas installé par `nsi install base`. C'est ce `--arg`
qui cassait la recherche d'équipe : avec `set -euo pipefail`, `nsi init`
mourait sur « unknown flag: --arg », avant même son message d'erreur. Le filtre
est donc un `awk`, choisi plutôt qu'un `grep` parce qu'il rend 0 même sans
correspondance, un `grep` muet ferait échouer l'affectation sous `pipefail` -
et les classes de chiffres y sont écrites en clair, les intervalles `{4}`
n'étant pas garantis par tous les `awk`.

- `git config user.name` = pseudo GitHub (pas de nom réel demandé).
- `git config user.email` = `<pseudo>@users.noreply.github.com` : l'API `/user`
  ne rend l'email que s'il est public (rare), et lire l'email privé exigerait
  la portée `user:email` en plus.
- `gh auth login --with-token` n'authentifie que `gh`. `gh auth setup-git` est
  appelé juste après pour l'enregistrer comme credential helper, sans ça,
  `nsi push`/`nsi pull`, qui appellent `git` directement, ne le seraient pas.

Clone ensuite le dépôt dans `~/<équipe>`, lance `uv sync`, ouvre VSCode.
**Ne déploie aucun fichier** : ils viennent du modèle dont le dépôt est issu.

**Ne supprime jamais rien.** Si `~/<équipe>` est déjà un dépôt git, il est
gardé tel quel ; s'il existe sans être un dépôt git, la commande s'arrête et le
dit. La version précédente commençait par `rm -rf "$HOME/$equipe"` : relancer
`nsi init`, ce qu'on demande à l'élève au moindre souci de jeton, effaçait tout
ce qui n'était pas poussé.

### Où vit le dépôt de l'élève

`push`, `pull` et `reset-config` travaillaient dans le répertoire courant.
Lancés depuis `~`, le premier faisait `git add -A` sur le dossier personnel et
le dernier y déversait `.vscode/`, `pyproject.toml` et `.gitignore`.

Le chemin est donc **mémorisé** par `nsi init` dans `~/.config/nsi/dossier`, et
les trois commandes commencent par `aller_dans_le_depot`. Une variable shell ne
suffirait pas : chaque `nsi` est un nouveau processus. Et le recalculer
demanderait un appel à l'API GitHub, réseau et authentification, à chaque
`nsi push`.

- `nsi init` n'écrit le chemin que si `<dossier>/.git` existe : un clone échoué
  laisserait sinon un chemin mensonger.
- `dossier_eleve` revérifie `.git` à chaque lecture : le dossier a pu être
  renommé ou supprimé à la main. Dans ce cas, message clair et renvoi vers
  `nsi init`.
- **`nsi dir`** l'imprime, et rien d'autre : c'est la seule commande de `nsi`
  faite pour être composée. `setup.sh` et `Open-ConsoleDebian` l'utilisent
  (`code "$(nsi dir)"`) plutôt que de lire `~/.config/nsi/dossier`, dont le
  chemin et le format ne regardent que `nsi`.

> **TODO : idempotence de l'ouverture de VSCode en fin d'installation Windows.**
>
> Sur le parcours Windows, **deux appels à `code` ont lieu à chaque exécution** :
> `setup.sh` en ouvre un (il trouve `/dev/tty`, donc il prend sa branche
> interactive), puis `Open-ConsoleDebian` en ouvre un second. Seul `nsi init`
> est gardé par `nsi dir`, pas l'ouverture de l'éditeur.
>
> L'effet visible est faible, `code` sur un dossier déjà ouvert remet la
> fenêtre au premier plan plutôt que d'en créer une seconde. Mais c'est un
> appel de trop, et c'est probablement le premier des deux qui tombe pendant
> l'installation du serveur VSCode, d'où le « Exec format error » observé.
>
> À trancher : qui ouvre VSCode sur ce parcours. Trois pistes, aucune testée.
> Laisser `setup.sh` le faire et retirer l'appel de la console finale. Ou
> l'inverse, et rendre `setup.sh` muet quand il tourne sous WSL. Ou déplacer
> l'ouverture côté PowerShell avec `code --remote wsl+Debian <dossier>`, qui ne
> traverse ni script Linux ni interop.

**Ouvrir VSCode n'est jamais fatal.** Le tout premier `code <dossier>` lancé
depuis WSL déclenche le téléchargement du serveur VSCode dans la distribution,
par `wslCode.sh` : pendant cette installation, l'appel peut échouer une fois
(« Exec format error » sur `Code.exe`), puis fonctionner ensuite. Constaté le
2026-09-11. `setup.sh` comme `Open-ConsoleDebian` rattrapent donc l'échec et
disent quoi retaper : l'environnement est installé et le dépôt cloné de toute
façon, et un `set -e` sur cette ligne tuerait tout à la dernière étape.

**Ouvrir VSCode n'appartient qu'aux scripts d'amorçage**, pas à `nsi init` :
lancer un éditeur est une commodité de première mise en route, pas le travail
d'une commande qui configure et clone. `setup.sh` le fait sur Mac et Linux,
`Open-ConsoleDebian` sur Windows.

### Rien n'avance tant que `nsi init` n'a pas abouti

Un débutant se trompe de portée, colle un jeton tronqué, ou n'a pas accepté ses
invitations. Chacun de ces cas tuait l'installation et l'obligeait à tout
relancer. Trois boucles l'évitent :

- **le jeton** : tant que `gh auth login --with-token` refuse, on réexplique
  les trois portées et on redemande ;
- **le dépôt** : tant qu'aucun ne correspond, on affiche les URL des
  invitations et on attend une touche pour réessayer ;
- **`setup.sh`** : `while ! nsi init`, il n'ouvre pas VSCode sur un dossier
  inexistant.

Chaque boucle se termine si `read` échoue. Sans terminal il rend EOF
immédiatement, et on tournerait sans fin sans que personne ne puisse répondre :
vérifié, la boucle rend la main au lieu de s'emballer.

### `nsi reset-config`

Retélécharge les fichiers de configuration depuis `nsi-bf/template-eleves` et
les écrase. Commande explicite, avec avertissement à l'élève : elle réinitialise
`pyproject.toml`, donc ses `uv add`.

### `nsi push` / `nsi pull`

`git add -A && git commit -m "Sauvegarde du <date>" && git push`, sans erreur
si rien n'a changé. Et `git pull`.
