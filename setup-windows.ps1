# Amorçage Windows de l'environnement NSI.
#
#   irm https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup-windows.ps1 | iex
#
# A coller dans PowerShell, pas dans cmd : depuis cmd, le detecteur de menaces
# de Windows refuse la commande. L'execution en memoire de code telecharge est
# le motif des chargeurs de logiciels malveillants, et le processus parent
# entre dans l'heuristique.
#
# Rôle unique : fabriquer une machine Linux utilisable, puis passer la main à
# setup.sh. Ce script n'installe aucun outil pédagogique : ni nsi, ni uv, ni
# gleam. Il sert deux situations, décrites au-dessus de Get-BesoinAdmin.
#
# Le fichier est en UTF-8 SANS BOM, et ça ne doit pas changer : `iex` sur une
# chaîne qui commence par un BOM échoue (« le terme ?Write-Host n'est pas
# reconnu »), mesuré le 2026-09-11 sous Windows PowerShell 5.1. Les accents
# passent quand même, GitHub raw servant `charset=utf-8`, que `irm` respecte.

$ErrorActionPreference = "Stop"

# --- Journal ---
# Sans lui, on ne sait rien : la fenetre elevee peut se fermer avant qu'on ait
# pu lire quoi que ce soit, et une erreur d'analyse du script empeche meme le
# catch global de s'executer. Le fichier, lui, reste.
#
# Sur le Bureau plutot que dans %TEMP% : un eleve doit pouvoir le retrouver et
# l'envoyer sans qu'on lui explique ou chercher.
$Bureau = [Environment]::GetFolderPath("Desktop")
if ([string]::IsNullOrEmpty($Bureau)) { $Bureau = $env:TEMP }
$LogPath = Join-Path $Bureau "nsi-installation.log"
try { Start-Transcript -Path $LogPath -Append -Force | Out-Null } catch { }

$SetupUrl   = "https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup-windows.ps1"
$SetupShUrl = "https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup.sh"
$Distro     = "Debian"
$WslUser    = "padawan"
$WslPass    = "padawan"

# La clé des distributions WSL de CET utilisateur. Une distribution est
# enregistrée par utilisateur, pas par machine : c'est ici, et non dans une
# liste globale, que se lit ce que l'élève possède.
$LxssPath   = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss"

# Marqueur « le travail côté Windows n'est pas fini ». Posé juste avant de
# demander le redémarrage, effacé quand ce travail est terminé.
#
# Sans lui, le lancement qui suit le redémarrage est indiscernable d'un poste
# de lycée : les fonctionnalités WSL viennent d'être activées, donc le service
# `LxssManager` existe et VSCode est déjà installé, la sonde répondrait « WSL
# est là, rien à élever » alors que WSL n'a été ni mis à jour ni passé en
# version 2. Et comme un redémarrage est obligatoire sur toute machine neuve,
# ce n'est pas un cas rare : c'est le parcours normal.
$MarqueurPath = "HKCU:\SOFTWARE\nsi-bf"
$MarqueurNom  = "InstallationWindowsEnCours"

# Chemins résolus une fois, partagés par les étapes. Les fonctions qui les
# mettent à jour écrivent `$script:Wsl` / `$script:Code`.
$Wsl  = $null
$Code = $null


# ---------------------------------------------------------------- petits outils

function Write-Red($msg) { Write-Host $msg -ForegroundColor Red }

function Invoke-Native {
    & $args[0] $args[1..($args.Count-1)]
    if ($LASTEXITCODE -ne 0) { throw "Echec (code $LASTEXITCODE) : $args" }
}

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Arrêt net, avec la seule consigne qu'un élève puisse suivre. Appelé quand il
# manque quelque chose que lui ne peut pas installer : au lycée il n'est pas
# administrateur, et chez lui les voies de secours sont hors de sa portée.
function Stop-VoirLeProf($quoi) {
    Write-Red ""
    Write-Red $quoi
    Write-Red ""
    Write-Red "N'INSISTE PAS, DEMANDE DE L'ASSISTANCE A TON PROFESSEUR."
    Write-Red ""
    Write-Red "Un compte rendu a ete ecrit dans :"
    Write-Red "  $LogPath"
    Write-Red "Envoie ce fichier a ton professeur."
    Write-Red ""
    try { Stop-Transcript | Out-Null } catch { }
    Read-Host "Appuie sur entrée pour quitter"
    exit 1
}

# Windows Update (TrustedInstaller/TiWorker) verrouille les fichiers système
# utilisés par DISM et `wsl --install` : attendre, plutôt que de laisser
# l'élève croire que le script est figé pendant potentiellement 10+ minutes.
function Test-WindowsUpdateBusy {
    $ti = Get-Service -Name TrustedInstaller -ErrorAction SilentlyContinue
    if ($null -ne $ti -and $ti.Status -eq "Running") { return $true }
    if (Get-Process -Name TiWorker -ErrorAction SilentlyContinue) { return $true }
    return $false
}

function Wait-WindowsUpdateIdle {
    if (-not (Test-WindowsUpdateBusy)) { return }
    Write-Host "Windows Update est en cours d'installation, on patiente avant de continuer..." -ForegroundColor Yellow
    while (Test-WindowsUpdateBusy) {
        Start-Sleep -Seconds 10
        Write-Host "." -NoNewline
    }
    Write-Host ""
    Write-Host "Windows Update a terminé, reprise de l'installation." -ForegroundColor Green
}


# ------------------------------------- sondes : lire l'état sans rien déclencher

# wsl.exe n'existe que dans le System32 *natif*. Un PowerShell 32 bits qui lit
# System32 est redirigé par WOW64 vers SysWOW64, où il n'y a pas de wsl.exe :
# `Sysnative` est l'alias qui désigne le vrai System32 depuis un processus
# 32 bits. C'est écrit dans la doc de WSL. On résout donc le chemin plutôt que
# de compter sur le PATH.
function Get-WslPath {
    $natif = if ([Environment]::Is64BitProcess) { "$env:WINDIR\System32" } else { "$env:WINDIR\Sysnative" }
    $chemin = Join-Path $natif "wsl.exe"
    if (Test-Path $chemin) { return $chemin }
    $cmd = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# WSL est-il installé ? On ne le demande PAS à `wsl.exe` : invoqué alors que
# WSL n'est pas installé, il propose de s'installer et le fait au bout d'une
# trentaine de secondes, quelle que soit l'option passée. Une sonde qui
# déclenche ce qu'elle mesure n'est pas une sonde.
#
# On lit donc l'état, sans rien lancer. Deux noms de service, parce qu'il y a
# deux WSL : `LxssManager` pour le composant Windows historique, `WSLService`
# pour la version livrée par le Store, sur une machine à jour, c'est
# `WSLService` qui est là et `LxssManager` qui manque (mesuré le 2026-09-11,
# WSL 2.7.13.0). Le paquet Store sert de troisième filet.
function Test-WslInstalle {
    foreach ($nom in @("WSLService", "LxssManager")) {
        if ($null -ne (Get-Service -Name $nom -ErrorAction SilentlyContinue)) { return $true }
    }
    return ($null -ne (Get-AppxPackage -Name "MicrosoftCorporationII.WindowsSubsystemForLinux" `
                        -ErrorAction SilentlyContinue))
}

function Get-DistroKey($nom) {
    if (-not (Test-Path $LxssPath)) { return $null }
    Get-ChildItem $LxssPath -ErrorAction SilentlyContinue |
        Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DistributionName -eq $nom } |
        Select-Object -First 1
}

# VSCode peut être installé sans que `code` soit dans le PATH de ce processus :
# celui-ci est figé au démarrage, et l'installation machine comme utilisateur
# pose son propre dossier. On regarde donc aussi les emplacements connus, sinon
# on croirait VSCode absent et on demanderait l'élévation pour rien.
function Get-CodePath {
    $cmd = Get-Command code -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
        "${env:ProgramFiles(x86)}\Microsoft VS Code\bin\code.cmd")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Set-Marqueur {
    if (-not (Test-Path $MarqueurPath)) { New-Item -Path $MarqueurPath -Force | Out-Null }
    Set-ItemProperty -Path $MarqueurPath -Name $MarqueurNom -Value 1
}

function Test-Marqueur {
    if (-not (Test-Path $MarqueurPath)) { return $false }
    return ($null -ne (Get-ItemProperty -Path $MarqueurPath -Name $MarqueurNom -ErrorAction SilentlyContinue))
}

function Clear-Marqueur {
    if (Test-Marqueur) {
        Remove-ItemProperty -Path $MarqueurPath -Name $MarqueurNom -ErrorAction SilentlyContinue
    }
}

# Ce script sert deux situations.
#
# Chez l'élève, tout est à installer, et il est administrateur de sa machine.
# Au lycée, VSCode et WSL sont déjà là, posés par l'image du poste, et l'élève
# n'est PAS administrateur : demander l'élévation n'échouerait pas seulement,
# elle serait impossible.
#
# On ne lui demande pas où il est : la machine sait répondre, et un débutant
# peut se tromper. Tout ce qui exige l'administrateur, poser VSCode, activer
# les fonctionnalités Windows, mettre WSL à jour, ne sert qu'à obtenir ces
# deux choses-là. Si elles sont déjà là, il n'y a rien à élever.
#
# `Get-WindowsOptionalFeature -Online` exige l'administrateur (mesuré :
# « L'opération demandée nécessite une élévation »), donc il n'est consulté que
# dans la branche administrateur, où l'on est, par construction, élevé.
function Get-BesoinAdmin {
    if (Test-Marqueur) { return $true }
    $wslPresent = ($null -ne $script:Wsl) -and (Test-WslInstalle)
    return (-not $wslPresent) -or ($null -eq $script:Code)
}


# Ce que les sondes ont vu, en clair. Affiché dès qu'on conclut qu'il faut
# l'administrateur, et quand quelque chose échoue : sans ça, « cet ordinateur
# n'a pas tout ce qu'il faut » ne dit pas *quoi*, et il n'y a rien à corriger.
function Show-Diagnostic {
    $admin   = Test-Admin
    $bits    = [Environment]::Is64BitProcess
    $cheminW = if ($null -eq $script:Wsl)  { "<introuvable>" } else { $script:Wsl }
    $cheminC = if ($null -eq $script:Code) { "<introuvable>" } else { $script:Code }

    $svc = @(Get-Service -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match "lxss|wsl" } |
             ForEach-Object { $_.Name + "=" + $_.Status })
    $services = if ($svc.Count -eq 0) { "<aucun>" } else { $svc -join ", " }

    $store = "<absent>"
    try {
        $appx = Get-AppxPackage -Name "MicrosoftCorporationII.WindowsSubsystemForLinux" -ErrorAction SilentlyContinue
        if ($null -ne $appx) { $store = $appx.Version }
    } catch {
        $store = "<Get-AppxPackage a echoue : " + $_.Exception.Message + ">"
    }

    $wg = Get-Command winget -ErrorAction SilentlyContinue
    $winget = if ($null -eq $wg) { "<introuvable>" } else { $wg.Source }

    $distros = "<cle Lxss absente>"
    if (Test-Path $LxssPath) {
        $noms = @(Get-ChildItem $LxssPath -ErrorAction SilentlyContinue |
                  ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DistributionName })
        $distros = if ($noms.Count -eq 0) { "<aucune>" } else { $noms -join ", " }
    }

    Write-Host ""
    Write-Host "--- Etat detecte ---" -ForegroundColor Yellow
    Write-Host "  administrateur    : $admin"
    Write-Host "  processus 64 bits : $bits"
    Write-Host "  wsl.exe           : $cheminW"
    Write-Host "  services WSL      : $services"
    Write-Host "  paquet Store WSL  : $store"
    Write-Host "  code              : $cheminC"
    Write-Host "  winget            : $winget"
    Write-Host "  distributions     : $distros"
    Write-Host "  marqueur          : $(Test-Marqueur)"
    Write-Host "--------------------" -ForegroundColor Yellow
    Write-Host ""
}


# ------------------------------------------------------------------------ étapes

function Show-Accueil {
    Write-Host ""
    Write-Host "L'installation va commencer." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Tu dois rester connecté à Internet pendant toute l'installation :"
    Write-Host "presque tout ce qui s'installe est téléchargé au fur et à mesure."
    Write-Host ""
    Write-Host "Il se peut que le programme te demande de redémarrer ton ordinateur."
    Write-Host "Dans ce cas, redémarre-le et réexécute la même commande dans le"
    Write-Host "terminal."
    Write-Host ""
    Read-Host "Appuie sur entrée pour démarrer l'installation"
    Write-Host ""
}

# Relance le script élevé et rend la main au processus élevé. Ne revient que si
# on était déjà administrateur.
function Request-Admin {
    if (Test-Admin) { return }
    try {
        # -NoExit : sans lui, la fenetre elevee se ferme instantanement si le
        # script echoue avant son propre try/catch, par exemple sur une erreur
        # d'analyse. On ne verrait alors rien du tout.
        Start-Process PowerShell -Verb RunAs `
            -ArgumentList "-NoExit -ExecutionPolicy Bypass -Command `"irm '$SetupUrl' | iex`""
        exit
    } catch {
        # Refus de l'UAC, ou compte sans droit d'élévation. On dit laquelle :
        # le message seul ne laissait rien à corriger.
        Write-Red ""
        Write-Red "L'ELEVATION DES PRIVILEGES A ECHOUE."
        Write-Red "Detail : $($_.Exception.Message)"
        Show-Diagnostic
        Stop-VoirLeProf "CET ORDINATEUR N'A PAS TOUT CE QU'IL FAUT, ET JE NE PEUX PAS L'INSTALLER."
    }
}

# winget est livré avec Windows 11 et Windows 10 1809+, mais par le paquet App
# Installer du Microsoft Store, donc absent d'une édition N ou LTSC, d'un
# Windows 10 jamais mis à jour, ou d'un poste dont le Store a été désactivé ou
# abîmé. Et un winget ancien ne connaît pas `--accept-source-agreements`.
#
# S'il manque, on s'arrête. Les trois voies pour l'installer (Store,
# `Repair-WinGetPackageManager`, `.msixbundle` de GitHub) sont hors de portée
# d'un élève débutant : le module PowerShell exige PowerShell 7, qui n'est pas
# là, et le `.msixbundle` demande de poser des dépendances à la main. Mieux
# vaut un arrêt net qu'un débutant qui s'acharne seul sur son ordinateur.
#
# La mise à jour, elle, passe par winget lui-même : il se livre comme le paquet
# Microsoft.AppInstaller et sait donc se mettre à jour depuis la version 1.6.
# Silencieuse et jamais fatale, pour la même raison que celle de WSL, on ne
# sait pas distinguer « déjà à jour » d'un échec sans lire un message localisé.
function Initialize-Winget {
    if ($null -eq (Get-Command winget -ErrorAction SilentlyContinue)) {
        Stop-VoirLeProf "CET ORDINATEUR N'A PAS L'OUTIL NECESSAIRE (winget)."
    }
    Write-Host "Mise à jour de winget..."
    & winget upgrade --id Microsoft.AppInstaller --exact --silent `
        --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
}

function Install-VSCode {
    if ($null -eq $script:Code) {
        Write-Host "Installation de VSCode..."
        Invoke-Native winget install -e --id Microsoft.VisualStudioCode --silent `
            --accept-package-agreements --accept-source-agreements
        # L'installateur ajoute `code` au PATH, mais le PATH de ce processus a
        # été figé à son démarrage : `code` resterait introuvable jusqu'au
        # prochain terminal. On relit les deux portées, machine et utilisateur.
        $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("PATH", "User")
        $script:Code = Get-CodePath
    }
    if ($null -eq $script:Code) {
        Stop-VoirLeProf "VSCODE A ETE INSTALLE MAIS RESTE INTROUVABLE."
    }
}

# Active les fonctionnalités Windows de WSL2. Si l'une manquait, un
# redémarrage est indispensable : on le dit et on s'arrête.
function Enable-FonctionnalitesWsl {
    Wait-WindowsUpdateIdle
    $aRedemarrer = $false
    foreach ($feature in @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")) {
        if ((Get-WindowsOptionalFeature -Online -FeatureName $feature).State -ne "Enabled") {
            Write-Host "Activation de $feature..."
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null
            $aRedemarrer = $true
        }
    }
    if ($aRedemarrer) {
        # Pour que le lancement d'après ne se croie pas sur un poste de lycée.
        Set-Marqueur
        Write-Red ""
        Write-Red "REDEMARRE TON ORDINATEUR ET RELANCE LA MEME COMMANDE."
        Write-Red ""
        Read-Host "Appuie sur entrée pour quitter"
        exit 1
    }
}

# Un wsl.exe présent n'est pas un wsl.exe à jour : celui livré avec Windows
# date de l'image installée, et `wsl --install -d` échoue sur les versions
# anciennes.
#
# La mise à jour n'est jamais fatale. Trois raisons de la voir échouer sans que
# rien ne soit cassé : pas de réseau, le Microsoft Store indisponible, ou un
# wsl.exe trop ancien pour connaître `--update`. Dans les deux premiers cas
# `--web-download` passe par GitHub et s'en sort.
#
# Et elle est silencieuse dans tous les cas, y compris en échec. Le code de
# sortie de `wsl --update` sur un WSL déjà à jour n'a pas pu être mesuré : la
# commande arrête les distributions en cours, donc elle tue la session depuis
# laquelle on l'observe (constaté le 2026-09-11, 2.7.11.0 → 2.7.13.0). Sans
# savoir si ce code vaut 0, un avertissement conditionnel s'afficherait peut-
# être à chaque installation réussie, et un élève qui voit un avertissement
# chaque fois apprend à ne plus les lire. Un WSL réellement trop vieux se
# signalera à l'étape suivante, où `wsl --install -d` échouera pour de bon.
function Update-Wsl {
    Write-Host "Mise à jour de WSL..."
    & $script:Wsl --update 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & $script:Wsl --update --web-download 2>&1 | Out-Null
    }
    # La mise à jour remplace le service et le noyau : ce qui tourne encore est
    # l'ancien tant qu'on ne l'a pas arrêté. `--update` le fait déjà, mais rien
    # ne garantit qu'il l'ait fait quand il a échoué.
    try { & $script:Wsl --shutdown } catch {}
}

# Tout ce qui exige l'administrateur, et rien d'autre.
function Install-CoteWindows {
    # Le service WSL peut rester bloqué suite à une mise à jour Windows ou une
    # exécution précédente interrompue ; un shutdown repart sur une base saine.
    # Réservé à ce cas : au lycée, ça couperait les autres fenêtres de l'élève.
    #
    # `Test-WslInstalle` est indispensable ici : que le binaire existe ne dit
    # pas que WSL est installé, et `wsl.exe` invoqué sur une machine sans WSL
    # propose de s'installer puis le fait au bout d'une trentaine de secondes.
    if (($null -ne $script:Wsl) -and (Test-WslInstalle)) {
        try { & $script:Wsl --shutdown } catch {}
    }

    Initialize-Winget
    Install-VSCode
    Enable-FonctionnalitesWsl

    # Les fonctionnalités sont actives : wsl.exe doit exister maintenant. Il
    # est livré avec Windows 10 2004 (build 19041) et Windows 11, mais manque
    # sur les versions antérieures et sur certaines installations abîmées.
    $script:Wsl = Get-WslPath
    if ($null -eq $script:Wsl) {
        Stop-VoirLeProf "WSL EST INTROUVABLE SUR CET ORDINATEUR (Windows trop ancien ?)."
    }

    Update-Wsl
    Invoke-Native $script:Wsl --set-default-version 2

    # Le travail côté Windows est fait : plus besoin de forcer cette branche.
    Clear-Marqueur
}

# Dans les deux cas, y compris au lycée : les extensions VSCode s'installent
# par utilisateur, dans son profil. Que l'image du poste porte VSCode ne dit
# rien de ce que l'élève a dans le sien, et sans cette extension il ne peut pas
# ouvrir son dossier WSL depuis VSCode, c'est-à-dire travailler. Elle ne
# demande aucun droit et ne fait rien si elle est déjà là.
function Install-ExtensionWsl {
    Invoke-Native $script:Code --install-extension ms-vscode-remote.remote-wsl
}

# Présence lue au registre, pas par `wsl --list --quiet` : cette liste sort en
# UTF-16 et demandait de basculer l'encodage de la console le temps de l'appel,
# pour une comparaison de chaînes fragile. La clé, elle, est sans ambiguïté.
function Install-Debian {
    Wait-WindowsUpdateIdle
    if ($null -eq (Get-DistroKey $Distro)) {
        Write-Host "Installation de Debian..."
        Invoke-Native $script:Wsl --install -d $Distro --no-launch
        # Après une installation fraîche (noyau WSL2 compris), le service WSL
        # reste parfois dans un état incohérent tant qu'il n'a pas été relancé :
        # sans ce shutdown, la première commande wsl qui suit peut hang ou
        # échouer.
        Invoke-Native $script:Wsl --shutdown
    }
    # Première initialisation en root (bypasse l'OOBE)
    Invoke-Native $script:Wsl -d $Distro -u root -- true
}

function New-UtilisateurPadawan {
    Write-Host "Configuration de l'utilisateur $WslUser..."
    Invoke-Native $script:Wsl -d $Distro -u root -- bash -c "useradd -m -s /bin/bash $WslUser 2>/dev/null; echo '${WslUser}:${WslPass}' | chpasswd; usermod -aG sudo $WslUser"
}

# Le NOPASSWD est indispensable : l'installation qui suit est lancée sans
# terminal, personne ne pourrait taper un mot de passe. Révoqué dès la fin,
# y compris si setup.sh échoue, d'où le `finally`.
function Install-EnvironnementEleve {
    Invoke-Native $script:Wsl -d $Distro -u root -- bash -c "echo '$WslUser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$WslUser && chmod 440 /etc/sudoers.d/$WslUser"
    try {
        # curl, seul paquet posé d'ici : c'est lui qui ira chercher setup.sh.
        Invoke-Native $script:Wsl -d $Distro -u root -- bash -c "apt-get update -qq && apt-get install -y -qq curl"

        Write-Host "Installation de l'environnement de développement..."
        Invoke-Native $script:Wsl -d $Distro -u $WslUser -- bash -c "curl -fsSL $SetupShUrl | bash"
    } finally {
        Invoke-Native $script:Wsl -d $Distro -u root -- rm -f /etc/sudoers.d/$WslUser
    }
}

function Set-PadawanParDefaut {
    Invoke-Native $script:Wsl -d $Distro -u root -- bash -c "printf '[user]\ndefault=$WslUser\n' > /etc/wsl.conf"

    # Aussi via le registre, pour les versions de WSL qui ignorent wsl.conf
    # pour le DefaultUid.
    $uid = [int]((& $script:Wsl -d $Distro -u root -- id -u $WslUser) -replace '\D')
    $cle = Get-DistroKey $Distro
    if ($null -ne $cle -and $uid -gt 0) {
        Set-ItemProperty $cle.PSPath -Name DefaultUid -Value $uid -ErrorAction SilentlyContinue
    }
    Invoke-Native $script:Wsl --terminate $Distro
}

function Open-ConsoleDebian {
    Write-Host ""
    Write-Host "Installation terminée !" -ForegroundColor Green
    Write-Host ""
    Write-Host "Une console Debian va s'ouvrir. Suis les instructions pour configurer ton compte GitHub." -ForegroundColor Cyan
    # `bash -lc`, pas `bash -c` : un shell de connexion lit ~/.profile, donc
    # ~/.local/bin entre dans le PATH et `nsi` est trouvable. Mesuré sur une
    # Debian, environnement vierge : `bash -c` donne
    # /usr/local/bin:/usr/bin:/bin:/sbin et rien d'autre, `nsi init` échouerait
    # sur un « command not found » dès la console finale.
    # `nsi dir` imprime le dossier de cours, que seul `nsi init` connaît : il
    # dépend de l'équipe GitHub de l'élève. Le `$` est échappé en `` `$ `` pour
    # que PowerShell le laisse à bash.
    Start-Process $script:Wsl -ArgumentList "-d $Distro -u $WslUser -- bash -lc `"cd ~ && nsi init && code `$(nsi dir); exec bash -l`""
}


# ----------------------------------------------------------------------- déroulé

try {
    $Wsl  = Get-WslPath
    $Code = Get-CodePath
    $besoinAdmin = Get-BesoinAdmin

    # L'élévation d'abord, le mot d'accueil ensuite : dans l'autre ordre,
    # l'élève lit le texte, appuie sur entrée, accepte l'UAC, et retrouve le
    # même texte et la même attente dans la fenêtre élevée.
    if ($besoinAdmin) {
        # Dit pourquoi on va demander l'élévation. Quand elle n'était pas
        # nécessaire, c'est ici qu'on voit laquelle des deux sondes se trompe.
        Write-Host "Il manque quelque chose cote Windows, je demande les droits administrateur."
        Show-Diagnostic
        Request-Admin          # ne revient que si on est déjà administrateur
    }

    Show-Accueil

    if ($besoinAdmin) {
        Install-CoteWindows
    } else {
        # Au lycée : VSCode et WSL sont posés par l'image du poste, et l'élève
        # n'a pas les droits pour y toucher. On va droit à sa Debian, la seule
        # chose qui lui manque.
        Write-Host "VSCode et WSL sont déjà installés sur cet ordinateur."
        Write-Host ""
    }

    Install-ExtensionWsl
    Install-Debian
    New-UtilisateurPadawan
    Install-EnvironnementEleve
    Set-PadawanParDefaut
    Open-ConsoleDebian
} catch {
    Write-Host ""
    Write-Red "ERREUR : $_"
    Write-Red "Ligne  : $($_.InvocationInfo.ScriptLineNumber) - $($_.InvocationInfo.Line.Trim())"
    try { Show-Diagnostic } catch {}
    Write-Red "Compte rendu ecrit dans : $LogPath"
    Write-Red "Envoie ce fichier a ton professeur."
    Write-Host ""
    try { Stop-Transcript | Out-Null } catch { }
    Read-Host "Appuie sur entrée pour quitter"
    exit 1
}

try { Stop-Transcript | Out-Null } catch { }
Read-Host "Appuie sur entrée pour quitter"
