$ErrorActionPreference = "Stop"

try {

$SetupUrl  = "https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup-windows.ps1"
$SetupShUrl = "https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup.sh"
$Distro    = "Debian"
$WslUser   = "padawan"
$WslPass   = "padawan"

function Write-Red($msg) { Write-Host $msg -ForegroundColor Red }

function Invoke-Native {
    & $args[0] $args[1..($args.Count-1)]
    if ($LASTEXITCODE -ne 0) { throw "Echec (code $LASTEXITCODE) : $args" }
}

# Windows Update (TrustedInstaller/TiWorker) verrouille les fichiers systeme
# utilisés par DISM et wsl --install : attendre plutôt que de laisser
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

# Élévation automatique si pas admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -Verb RunAs `
        -ArgumentList "-ExecutionPolicy Bypass -Command `"irm '$SetupUrl' | iex`""
    exit
}

# Le service WSL peut rester bloqué suite à une mise à jour Windows ou une
# exécution précédente interrompue ; un shutdown systématique en début de
# script repart sur une base saine (idempotent, ne casse rien si WSL est
# absent ou déjà arrêté).
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    try { wsl --shutdown } catch {}
}

# 1. VSCode
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Host "Installation de VSCode..."
    Invoke-Native winget install -e --id Microsoft.VisualStudioCode --silent `
        --accept-package-agreements --accept-source-agreements
}
Invoke-Native code --install-extension ms-vscode-remote.remote-wsl

# 2. Fonctionnalités Windows pour WSL
Wait-WindowsUpdateIdle
$needsRestart = $false
foreach ($feature in @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")) {
    if ((Get-WindowsOptionalFeature -Online -FeatureName $feature).State -ne "Enabled") {
        Write-Host "Activation de $feature..."
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null
        $needsRestart = $true
    }
}

if ($needsRestart) {
    Write-Red ""
    Write-Red "REDEMARREZ VOTRE ORDINATEUR ET RELANCEZ LA COMMANDE."
    Write-Red ""
    Read-Host "Appuyez sur Entree pour quitter"
    exit 1
}

# 3. WSL version 2 par défaut
Invoke-Native wsl --set-default-version 2

# 4. Installation de Debian
Wait-WindowsUpdateIdle
$prevEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::Unicode
$wslDistros = wsl --list --quiet 2>&1
[Console]::OutputEncoding = $prevEncoding
if ($wslDistros -notcontains $Distro) {
    Write-Host "Installation de Debian..."
    Invoke-Native wsl --install -d $Distro --no-launch
    # Après une installation fraîche (noyau WSL2 compris), le service WSL
    # reste parfois dans un état incohérent tant qu'il n'a pas été relancé :
    # sans ce shutdown, la première commande wsl qui suit peut hang ou échouer.
    Invoke-Native wsl --shutdown
}
# Première initialisation en root (bypasse l'OOBE)
Invoke-Native wsl -d $Distro -u root -- true

# 5. Utilisateur padawan
Write-Host "Configuration de l'utilisateur $WslUser..."
Invoke-Native wsl -d $Distro -u root -- bash -c "useradd -m -s /bin/bash $WslUser 2>/dev/null; echo '${WslUser}:${WslPass}' | chpasswd; usermod -aG sudo $WslUser"

# 6. Sudo sans mot de passe pour padawan
# Nécessaire parce que l'installation qui suit est lancée sans terminal : il n'y
# aurait personne pour taper un mot de passe. Révoqué dès qu'elle est finie.
Invoke-Native wsl -d $Distro -u root -- bash -c "echo '$WslUser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$WslUser && chmod 440 /etc/sudoers.d/$WslUser"

# 7. curl, seul paquet posé d'ici : c'est lui qui ira chercher setup.sh.
Invoke-Native wsl -d $Distro -u root -- bash -c "apt-get update -qq && apt-get install -y -qq curl"

# 8. Passage de main à setup.sh, qui installe l'environnement élève.
# Ce script-ci ne connaît aucun outil pédagogique : ni nsi, ni uv, ni gleam.
Write-Host "Installation de l'environnement de développement..."
Invoke-Native wsl -d $Distro -u $WslUser -- bash -c "curl -fsSL $SetupShUrl | bash"

# Révocation du sudo sans mot de passe
Invoke-Native wsl -d $Distro -u root -- rm -f /etc/sudoers.d/$WslUser

# 9. Définir padawan comme utilisateur par défaut
Invoke-Native wsl -d $Distro -u root -- bash -c "printf '[user]\ndefault=$WslUser\n' > /etc/wsl.conf"

# Aussi via le registre Windows (pour les versions WSL qui ignorent wsl.conf pour le DefaultUid)
$padawanUid = [int]((wsl -d $Distro -u root -- id -u $WslUser) -replace '\D')
$lxssPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss"
$debianKey = Get-ChildItem $lxssPath -ErrorAction SilentlyContinue |
    Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DistributionName -eq $Distro } |
    Select-Object -First 1
if ($null -ne $debianKey -and $padawanUid -gt 0) {
    Set-ItemProperty $debianKey.PSPath -Name DefaultUid -Value $padawanUid -ErrorAction SilentlyContinue
}

Invoke-Native wsl --terminate $Distro

Write-Host ""
Write-Host "Installation terminée !" -ForegroundColor Green
Write-Host ""
Write-Host "Une console Debian va s'ouvrir. Suis les instructions pour configurer ton compte GitHub." -ForegroundColor Cyan

# Ouverture d'une console Debian interactive pour lancer nsi git
Start-Process wsl -ArgumentList "-d $Distro -u $WslUser -- bash -c `"cd ~ && nsi git; exec bash`""

} catch {
    Write-Host ""
    Write-Red "ERREUR : $_"
    Write-Host ""
    Read-Host "Appuyez sur Entree pour quitter"
    exit 1
}
Read-Host "Appuyez sur Entree pour quitter"
