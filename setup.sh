#!/usr/bin/env bash
# setup.sh, amorçage de l'environnement élève sur WSL, Linux ou macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup.sh | bash
#
# Rôle unique : poser `nsi` chez l'utilisateur, lui faire installer la base, et
# s'assurer qu'il sera trouvable ensuite. Il ne connaît aucun composant
# pédagogique : c'est `nsi` qui les porte.
#
# Il tourne dans deux contextes, dont un sans terminal : setup-windows.ps1
# l'appelle par `wsl -u padawan -- bash -c "curl … | bash"`. Rien ici ne doit
# donc attendre une saisie, pas de `read`, pas de question.

set -euo pipefail

NSI_URL="https://raw.githubusercontent.com/nsi-bf/scripts-install/main/nsi"
# nsi vit chez l'utilisateur : ni son installation ni sa mise à jour n'exigent
# sudo, et sur macOS Homebrew refuse d'être lancé en root.
INSTALL_PATH="$HOME/.local/bin/nsi"

# --- Jamais en root ---
# `curl … | sudo bash` poserait nsi dans /root/.local/bin, invisible pour
# l'élève, et casserait Homebrew sur macOS. Chaque opération qui a besoin de
# root l'appelle elle-même, en interne.
if [ "$(id -u)" -eq 0 ]; then
    echo "Erreur : ne lance pas ce script avec sudo." >&2
    echo "Relance-le simplement, sans rien devant :" >&2
    echo "  curl -fsSL ${NSI_URL%/nsi}/setup.sh | bash" >&2
    exit 1
fi

echo ""
echo "Installation de ton environnement de développement."
echo ""
echo "Reste connecté à Internet pendant toute l'installation : presque tout"
echo "ce qui s'installe est téléchargé au fur et à mesure."
echo "Ton mot de passe peut être demandé pour installer des paquets système."
echo ""

# --- curl ---
# Seul paquet système que ce script pose lui-même. Normalement déjà là, il
# arrive lui-même par curl, sauf sur une Debian WSL fraîche, où
# setup-windows.ps1 l'a installé juste avant.
if ! command -v curl &>/dev/null; then
    echo "Installation de curl..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq curl
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y -q curl
    else
        echo "Erreur : curl est absent et je ne sais pas l'installer ici." >&2
        exit 1
    fi
fi

# --- nsi ---
echo "Installation de nsi dans $INSTALL_PATH..."
mkdir -p "$(dirname "$INSTALL_PATH")"
# On télécharge à côté puis on renomme : le renommage est atomique, on ne
# laisse jamais un nsi à moitié écrit derrière soi.
tmp="$(mktemp "${INSTALL_PATH}.XXXXXX")"
curl -fsSL "$NSI_URL" -o "$tmp"
chmod +x "$tmp"
mv "$tmp" "$INSTALL_PATH"

# --- Le PATH de demain ---
# Poser nsi ne suffit pas : il faut qu'un shell de connexion le trouve, sinon
# le `nsi init` qu'on annonce plus bas échoue sur un « command not found ».
#
# Sur Debian, `~/.profile` ajoute `~/.local/bin` *si le dossier existe*, il
# vient d'être créé, donc c'est réglé. Sur macOS le shell par défaut est zsh,
# qui ne lit pas `~/.profile` du tout : sans cette fonction, `nsi` ne serait
# jamais dans le PATH.
#
# On n'écrit rien si un shell de connexion résout déjà `nsi` : inutile de
# salir le profil de quelqu'un dont la configuration marche.
assurer_path() {
    local shell_connexion="${SHELL:-/bin/bash}"

    # `env -i` est indispensable : sans lui, le shell de connexion hérite du
    # PATH de celui-ci, et la sonde répond « c'est bon » alors que l'élève,
    # dans un terminal neuf, ne trouvera rien. On repart donc d'un
    # environnement vide, comme à l'ouverture d'une session.
    if env -i HOME="$HOME" "$shell_connexion" -lc 'command -v nsi' >/dev/null 2>&1; then
        return 0
    fi

    # Le fichier lu par le shell de connexion. bash lit ~/.bash_profile *à la
    # place* de ~/.profile quand il existe, d'où l'ordre.
    local fichier
    case "$shell_connexion" in
        *zsh)  fichier="$HOME/.zprofile" ;;
        *)
            if   [ -f "$HOME/.bash_profile" ]; then fichier="$HOME/.bash_profile"
            elif [ -f "$HOME/.bash_login" ];   then fichier="$HOME/.bash_login"
            else                                    fichier="$HOME/.profile"
            fi
            ;;
    esac

    if [ -f "$fichier" ] && grep -qF '.local/bin' "$fichier"; then
        return 0
    fi

    echo "Ajout de ~/.local/bin au PATH dans $fichier..."
    {
        echo ""
        echo "# Ajouté par le script d'installation NSI"
        # shellcheck disable=SC2016  # $HOME doit rester littéral : il s'expanse
        # à l'ouverture de session, pas maintenant.
        echo 'export PATH="$HOME/.local/bin:$PATH"'
    } >> "$fichier"
}

assurer_path

# --- Les outils ---
# Appelé par chemin absolu : ~/.local/bin n'est pas encore dans le PATH de ce
# shell-ci, et ne le sera qu'à la prochaine connexion.
"$INSTALL_PATH" install base

# --- La suite : nsi init ---
#
# Elle est interactive, elle demande un jeton GitHub, et deux choses
# l'empêchent de lire le clavier telle quelle :
#
#   1. sous `curl … | bash`, stdin est le tuyau de curl. Un `read` n'y trouve
#      pas le clavier mais ce qui reste du script, ou EOF ;
#   2. il n'y a pas toujours de terminal de contrôle. `setup-windows.ps1`
#      appelle ce script par `wsl -- bash -c "curl … | bash"`, sans console.
#
# D'où la lecture depuis /dev/tty, et le test qui l'ouvre vraiment : le fichier
# existe même quand aucun terminal n'y répond, donc `[ -e /dev/tty ]` ne suffit
# pas à décider.
#
# Ce test répond oui plus souvent qu'on ne croit. Lancé par `wsl.exe` depuis
# une console PowerShell, ce script trouve /dev/tty ouvrable, alors même que
# stdin est le tuyau de curl (mesuré le 2026-09-11). C'est donc lui qui
# configure GitHub sur le parcours Windows, et la console ouverte ensuite par
# setup-windows.ps1 ne relance `nsi init` que s'il reste à faire.
#
# Sans terminal, on ne tente rien : c'est alors cette console finale qui s'en
# charge, et l'élève y tapera son jeton.
echo ""
if (exec </dev/tty) 2>/dev/null; then
    echo "Installation terminée. Configuration de ton compte GitHub."
    echo ""
    "$INSTALL_PATH" init </dev/tty

    # Ouvrir VSCode est une commodité d'amorçage : c'est ici qu'elle a sa
    # place, pas dans `nsi init`, qui se contente de configurer et de cloner.
    # Le dossier n'est connu qu'après coup, il dépend de l'équipe GitHub de
    # l'élève, et c'est `nsi dir` qui le dit, pour ne pas coder ici le chemin
    # de l'état interne de nsi.
    # `code` est gardé : `set -e` ferait mourir le script sur sa dernière
    # ligne, après que tout a réussi, si VSCode n'était pas installé ou si sa
    # commande n'était pas dans le PATH, ce qui arrive sur macOS tant que
    # « Install 'code' command in PATH » n'a pas été lancé depuis VSCode.
    if dossier="$("$INSTALL_PATH" dir 2>/dev/null)"; then
        if command -v code &>/dev/null; then
            echo ""
            echo "Ouverture de VSCode..."
            code "$dossier"
        else
            echo ""
            echo "Ouvre VSCode, puis ouvre ce dossier :  $dossier"
        fi
    fi
else
    echo "Installation terminée."
    echo ""
    echo "Ouvre un nouveau terminal, puis lance :  nsi init"
fi
