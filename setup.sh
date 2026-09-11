#!/usr/bin/env bash
# setup.sh — amorçage de l'environnement élève sur WSL, Linux ou macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup.sh | bash
#
# Rôle unique : poser `nsi` chez l'utilisateur et lui faire installer la base.
# Il ne connaît aucun composant pédagogique : c'est `nsi` qui les porte.
# Identique sur les trois plateformes, aucune condition à écrire.

set -euo pipefail

NSI_URL="https://raw.githubusercontent.com/nsi-bf/scripts-install/main/nsi"
# nsi vit chez l'utilisateur : ni son installation ni sa mise à jour n'exigent
# sudo. ~/.local/bin est dans le PATH via le ~/.profile standard.
INSTALL_PATH="$HOME/.local/bin/nsi"

# curl est un paquet système : c'est la seule chose que ce script installe en
# root. Normalement déjà là — ce script arrive lui-même par curl — sauf sur une
# Debian WSL fraîche, où setup-windows.ps1 l'a posé juste avant.
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

echo "Installation de nsi dans $INSTALL_PATH..."
mkdir -p "$(dirname "$INSTALL_PATH")"
# On télécharge à côté puis on renomme : le renommage est atomique, on ne
# laisse jamais un nsi à moitié écrit derrière soi.
tmp="$(mktemp "${INSTALL_PATH}.XXXXXX")"
curl -fsSL "$NSI_URL" -o "$tmp"
chmod +x "$tmp"
mv "$tmp" "$INSTALL_PATH"

"$INSTALL_PATH" install base

echo ""
echo "Installation terminée."
echo ""
echo "Ouvre un nouveau terminal, puis lance :  nsi git"
