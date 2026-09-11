#!/usr/bin/env bash
set -euo pipefail

GITHUB_ORG="nsi-bf"
GITHUB_RAW_URL="https://raw.githubusercontent.com/nsi-bf/scripts-install/main/nsi"
# Les fichiers de configuration de l'élève vivent dans le dépôt template, seule
# source de vérité. Il est privé : on y accède par `gh api` avec le jeton de
# l'élève, jamais par curl qui n'en a pas.
TEMPLATE_REPO="template-eleves"
TEMPLATE_FICHIERS=(.vscode/settings.json .vscode/extensions.json
                   pyproject.toml .gitignore)
# nsi vit chez l'utilisateur : ni son installation ni sa mise à jour
# n'exigent sudo. ~/.local/bin passe avant /usr/local/bin dans le PATH.
INSTALL_PATH="$HOME/.local/bin/nsi"

# Où vit le dépôt de l'élève. Une variable shell ne survivrait pas d'une
# invocation à l'autre, chaque `nsi` est un nouveau processus, et le
# recalculer demanderait un appel à l'API GitHub, donc du réseau et une
# authentification, à chaque `nsi push`. On l'écrit donc une fois, dans
# `nsi init`, et les autres commandes le relisent.
# nsi installe des outils dans ~/.local/bin (uv, et lui-meme). Un shell de
# connexion l'a dans son PATH via ~/.profile, mais pas un shell ordinaire :
# `wsl -- bash -c` et le terminal de VSCode donnent
# /usr/local/bin:/usr/bin:/bin:/sbin et rien d'autre. `uv sync` echouait alors
# sur « uv: command not found » alors qu'uv etait bien installe. nsi regarde
# donc toujours la, sans dependre de la facon dont on l'a lance.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH

ETAT_DIR="$HOME/.config/nsi"
ETAT_DOSSIER="$ETAT_DIR/dossier"

# --- Détection OS ---

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }
is_mac() { [[ "$OSTYPE" == "darwin"* ]]; }
has_apt() { command -v apt-get &>/dev/null; }
has_dnf() { command -v dnf &>/dev/null; }
has_brew() { command -v brew &>/dev/null; }

ensure_brew() {
    has_brew && return 0
    is_mac || return 0
    echo "Installation de Homebrew..."
    # Avec stdin branché sur un tuyau, le cas quand nsi est appelé depuis
    # `curl … | bash`, l'installeur Homebrew bascule de lui-même en mode non
    # interactif (`elif [[ ! -t 0 ]]`), et passe alors `sudo -n`, qui ne
    # demande jamais de mot de passe. Sur un Mac neuf il s'arrête aussitôt sur
    # « Need sudo access on macOS ». On lui rebranche donc un vrai terminal.
    if (exec </dev/tty) 2>/dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

_pkg_upgraded=false
pkg_install() {
    if is_mac; then ensure_brew; fi
    if has_apt; then
        if [[ "$_pkg_upgraded" == false ]]; then
            sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
            sudo env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
            _pkg_upgraded=true
        fi
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    elif has_dnf; then
        if [[ "$_pkg_upgraded" == false ]]; then
            sudo dnf upgrade -y
            _pkg_upgraded=true
        fi
        sudo dnf install -y "$@"
    elif has_brew; then
        # Homebrew refuse d'être lancé en root : jamais de sudo ici.
        if [[ "$_pkg_upgraded" == false ]]; then
            brew update
            brew upgrade
            _pkg_upgraded=true
        fi
        brew install "$@"
    else
        echo "Gestionnaire de paquets non supporté" >&2; exit 1
    fi
}

pkg_remove() {
    if has_apt; then
        sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@"
    elif has_dnf; then
        sudo dnf remove -y "$@"
    elif has_brew; then
        brew uninstall "$@"
    fi
}

# --- wget ---

install_wget() {
    command -v wget &>/dev/null && return 0
    pkg_install wget
}

remove_wget() { pkg_remove wget; }

# --- git ---

install_git() {
    command -v git &>/dev/null && return 0
    pkg_install git
}

remove_git() { pkg_remove git; }

# --- uv ---

install_uv() {
    command -v uv &>/dev/null && return 0
    # Destination imposée plutôt que laissée au hasard : l'installeur essaie
    # $XDG_BIN_HOME, puis $XDG_DATA_HOME/../bin, puis $HOME/.local/bin. Les
    # deux premières dépendent de variables qu'on ne contrôle pas, et uv
    # finirait ailleurs que là où nsi le cherche.
    UV_INSTALL_DIR="$HOME/.local/bin" curl -LsSf https://astral.sh/uv/install.sh | sh
}

remove_uv() {
    rm -f "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx" \
          "$HOME/.local/bin/uv-receipt.json"
    # Ménage d'une éventuelle installation système (ancienne version du script).
    if [[ -e /usr/local/bin/uv || -e /usr/local/bin/uvx ]]; then
        sudo rm -f /usr/local/bin/uv /usr/local/bin/uvx
    fi
}

# --- graphviz ---

install_graphviz() {
    command -v dot &>/dev/null && return 0
    pkg_install graphviz
}

remove_graphviz() { pkg_remove graphviz; }

# --- gh-cli ---

install_gh() {
    command -v gh &>/dev/null && return 0
    if has_apt; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        _pkg_upgraded=false
        pkg_install gh
    elif has_dnf; then
        sudo dnf install -y 'dnf-command(config-manager)'
        sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
        sudo dnf install -y gh
    elif has_brew; then
        brew install gh
    fi
}

remove_gh() {
    if has_apt; then
        pkg_remove gh
        sudo rm -f /etc/apt/sources.list.d/github-cli.list \
                   /usr/share/keyrings/githubcli-archive-keyring.gpg
    elif has_dnf; then
        sudo dnf remove -y gh
        sudo rm -f /etc/yum.repos.d/gh-cli.repo
    elif has_brew; then
        brew uninstall gh
    fi
}

# --- vscode ---

install_vscode() {
    is_wsl && return 0
    command -v code &>/dev/null && return 0
    if has_brew; then
        brew install --cask visual-studio-code
    elif has_apt; then
        # Le dépôt officiel Microsoft, comme pour gh. Sans cette branche, une
        # Debian sans snap n'installait rien : on tombait dans le `else`, qui
        # se contentait d'un message sur stderr, et `code` manquait ensuite.
        # La clé est posée telle quelle, en ASCII armé : apt accepte un
        # `signed-by` qui pointe sur un `.asc` depuis Debian 11. Passer par
        # `gpg --dearmor` supposerait `gnupg` installé, ce qui n'est pas
        # garanti sur une Debian minimale.
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
            | sudo dd of=/usr/share/keyrings/microsoft.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.asc] https://packages.microsoft.com/repos/code stable main" \
            | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        _pkg_upgraded=false
        pkg_install code
    elif has_dnf; then
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' \
            | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
        sudo dnf install -y code
    elif command -v snap &>/dev/null; then
        sudo snap install code --classic
    else
        echo "Installation de VSCode non supportée sur cet OS" >&2
    fi
}

remove_vscode() {
    is_wsl && return 0
    if has_brew; then
        brew uninstall --cask visual-studio-code
    elif has_dnf; then
        sudo dnf remove -y code
        sudo rm -f /etc/yum.repos.d/vscode.repo
    elif command -v snap &>/dev/null; then
        sudo snap remove code
    fi
}

# --- base ---

install_base() {
    install_wget
    install_git
    install_uv
    install_graphviz
    install_gh
    install_vscode
}

remove_base() {
    remove_wget
    remove_git
    remove_uv
    remove_graphviz
    remove_gh
    remove_vscode
}

# --- gleam ---

install_gleam() {
    if has_brew; then
        brew list gleam &>/dev/null || brew install gleam
        return 0
    fi
    if ! command -v erl &>/dev/null; then
        if has_apt; then
            # Le paquet "erlang" embarque wx, la doc, etc. : erlang-base +
            # erlang-eunit (dont gleam a besoin pour ses tests) suffisent.
            if [[ "$_pkg_upgraded" == false ]]; then
                sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
                sudo env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
                _pkg_upgraded=true
            fi
            sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                erlang-base erlang-eunit
        else
            pkg_install erlang
        fi
    fi
    if command -v gleam &>/dev/null; then return 0; fi
    local version arch bindir
    version=$(curl -fsSL https://api.github.com/repos/gleam-lang/gleam/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    case "$(uname -m)" in
        x86_64)  arch="x86_64-unknown-linux-musl" ;;
        aarch64) arch="aarch64-unknown-linux-musl" ;;
        *) echo "Architecture non supportée pour gleam: $(uname -m)" >&2; exit 1 ;;
    esac
    # Le binaire gleam s'installe au niveau utilisateur, sans sudo.
    # ~/.local/bin est ajouté au PATH par le ~/.profile standard de Debian.
    # (Erlang, lui, reste un paquet système : il n'existe pas de version
    # utilisateur raisonnable, et il est partagé par tous les projets.)
    bindir="$HOME/.local/bin"
    mkdir -p "$bindir"
    curl -fsSL "https://github.com/gleam-lang/gleam/releases/download/v${version}/gleam-v${version}-${arch}.tar.gz" \
        | tar xz -C "$bindir" gleam
    echo
    echo "gleam $version installé dans $bindir"
    case ":$PATH:" in
        *":$bindir:"*) ;;
        *) echo "Ouvre un nouveau terminal pour que $bindir entre dans ton PATH." ;;
    esac
}

remove_gleam() {
    if has_brew; then brew uninstall gleam erlang; return; fi
    rm -f "$HOME/.local/bin/gleam"
    # Ménage d'une éventuelle installation système (ancienne version du script).
    if [[ -e /usr/local/bin/gleam ]]; then
        sudo rm -f /usr/local/bin/gleam
    fi
    if has_apt; then
        sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y erlang-base erlang-eunit
    else
        pkg_remove erlang
    fi
}

# --- postgresql ---

install_postgresql() {
    # Sur dnf, psql (client) et postgresql-server sont des paquets séparés
    if has_dnf; then
        rpm -q postgresql-server &>/dev/null && return 0
    else
        command -v psql &>/dev/null && return 0
    fi
    if has_apt; then
        pkg_install postgresql
        sudo service postgresql start || true
        sudo su -c "psql -c \"ALTER USER postgres PASSWORD 'postgres';\"" postgres || true
        sudo su -c "psql -c \"CREATE ROLE dev SUPERUSER LOGIN PASSWORD 'dev';\"" postgres 2>/dev/null || true
    elif has_dnf; then
        pkg_install postgresql-server postgresql
        [[ -f /var/lib/pgsql/data/PG_VERSION ]] || sudo postgresql-setup --initdb
        sudo systemctl enable --now postgresql || true
        sudo su -c "psql -c \"ALTER USER postgres PASSWORD 'postgres';\"" postgres || true
        sudo su -c "psql -c \"CREATE ROLE dev SUPERUSER LOGIN PASSWORD 'dev';\"" postgres 2>/dev/null || true
    elif has_brew; then
        brew install postgresql
        brew services start postgresql || true
        psql postgres -c "CREATE ROLE dev SUPERUSER LOGIN PASSWORD 'dev';" 2>/dev/null || true
    fi
}

remove_postgresql() {
    if has_apt; then
        pkg_remove postgresql
    elif has_dnf; then
        sudo systemctl stop postgresql || true
        pkg_remove postgresql-server postgresql
    elif has_brew; then
        brew services stop postgresql || true
        brew uninstall postgresql
    fi
}

# --- openjdk ---

install_openjdk() {
    command -v javac &>/dev/null && return 0
    if has_apt; then
        pkg_install default-jdk
    elif has_dnf; then
        pkg_install java-latest-openjdk-devel
    elif has_brew; then
        brew install openjdk
        brew link --force --overwrite openjdk
    fi
}

remove_openjdk() {
    if has_apt; then
        pkg_remove default-jdk
    elif has_dnf; then
        pkg_remove java-latest-openjdk-devel
    elif has_brew; then
        brew uninstall openjdk
    fi
}

# --- nasm ---

install_nasm() {
    command -v nasm &>/dev/null && return 0
    pkg_install nasm
}

remove_nasm() { pkg_remove nasm; }

# --- rust ---

install_rust() {
    command -v rustc &>/dev/null && return 0
    if has_brew; then
        brew install rust
    else
        # Installation dans le répertoire de l'utilisateur (~/.rustup, ~/.cargo).
        # Surtout PAS de sudo : rustup doit appartenir à l'utilisateur, sinon
        # il écrit dans le profil shell de root, sans effet pour l'élève.
        # `-y` évite toute question ; rustup ajoute lui-même ~/.cargo/bin au
        # PATH (~/.profile et ~/.bashrc).
        # `--profile minimal` écarte rust-docs : 900 Mo de HTML généré, alors
        # que la même doc est en ligne sur doc.rust-lang.org. On récupère
        # clippy et rustfmt via -c, eux valent leur place.
        # Résultat mesuré : 602 Mo au lieu de 1,5 Go par poste.
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
            | sh -s -- -y --profile minimal -c clippy,rustfmt
        echo
        echo "Rust est installé dans ~/.cargo"
        echo "Ouvre un nouveau terminal, ou lance : . \"$HOME/.cargo/env\""
    fi
}

# --- c/c++ ---

install_c() {
    command -v gcc &>/dev/null && command -v gdb &>/dev/null && return 0
    if has_apt; then
        pkg_install build-essential gdb
    elif has_dnf; then
        pkg_install gcc gcc-c++ make gdb
    elif has_brew; then
        xcode-select --install 2>/dev/null || true
        brew list gdb &>/dev/null || brew install gdb
    fi
}

remove_c() {
    if has_apt; then
        pkg_remove build-essential gdb
    elif has_dnf; then
        pkg_remove gcc gcc-c++ make gdb
    elif has_brew; then
        brew uninstall gdb 2>/dev/null || true
        echo "Sur macOS, gcc est fourni par Xcode Command Line Tools (non désinstallable via nsi)." >&2
    fi
}

# --- prolog ---

install_prolog() {
    command -v swipl &>/dev/null && return 0
    if has_apt; then
        pkg_install swi-prolog
    elif has_dnf; then
        pkg_install pl
    elif has_brew; then
        brew install swi-prolog
    fi
}

remove_prolog() {
    if has_apt; then
        pkg_remove swi-prolog
    elif has_dnf; then
        pkg_remove pl
    elif has_brew; then
        brew uninstall swi-prolog
    fi
}

remove_rust() {
    if has_brew; then
        brew uninstall rust
    else
        # rustup se désinstalle lui-même : il retire ~/.rustup, ~/.cargo et les
        # lignes qu'il avait ajoutées aux profils shell.
        if [[ -x "$HOME/.cargo/bin/rustup" ]]; then
            "$HOME/.cargo/bin/rustup" self uninstall -y
        fi
        # Ménage d'une éventuelle installation système laissée par une version
        # précédente de ce script.
        if [[ -d /usr/local/rustup || -d /usr/local/cargo ]]; then
            sudo rm -rf /usr/local/rustup /usr/local/cargo
        fi
        # `-L` ne supprime que des liens symboliques, jamais un vrai binaire.
        # Un `if` plutôt qu'un `&&` : avec `set -e`, un échec de sudo doit
        # arrêter le script au lieu de passer inaperçu.
        local f
        for f in rustc cargo rustup rustfmt rustdoc rust-gdb rust-gdbgui \
                 rust-lldb rust-analyzer clippy-driver cargo-clippy cargo-fmt \
                 cargo-miri rls; do
            if [[ -L "/usr/local/bin/$f" ]]; then
                sudo rm -f "/usr/local/bin/$f"
            fi
        done
    fi
}

# --- hide ---

cmd_toggle_config() {
    local settings=".vscode/settings.json"
    [[ -f "$settings" ]] || { echo "Fichier $settings introuvable. Lance nsi init d'abord." >&2; exit 1; }
    python3 - "$settings" <<'EOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
exclude = data.get("files.exclude", {})
new_val = not all(v is True for v in exclude.values())
data["files.exclude"] = {k: new_val for k in exclude}
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("Fichiers " + ("masqués" if new_val else "affichés") + " dans l'Explorer VSCode.")
EOF
}

# `uv sync` sur un uv absent donne « uv: command not found », qui ne dit pas
# quoi faire. On le dit.
exiger_uv() {
    command -v uv &>/dev/null && return 0
    echo "Erreur : uv est introuvable." >&2
    echo "Relance l'installation des outils de base : nsi install base" >&2
    exit 1
}

# --- settings ---

cmd_reset_config() {
    aller_dans_le_depot
    local f present manquants=0

    # On ne réclame que ce que le modèle contient réellement. La liste
    # TEMPLATE_FICHIERS dit ce qui *peut* être repris, pas ce qui doit exister :
    # le contenu du modèle est tenu à part, et `nsi` n'a pas à savoir ce qui s'y
    # trouve aujourd'hui. Sans ce filtre, un fichier absent faisait échouer
    # `gh api` en 404 et, sous `set -euo pipefail`, tuait la commande entière.
    present="$(gh api "repos/$GITHUB_ORG/$TEMPLATE_REPO/git/trees/HEAD?recursive=1" \
        --jq '.tree[] | select(.type=="blob") | .path')"

    for f in "${TEMPLATE_FICHIERS[@]}"; do
        if ! grep -qxF "$f" <<< "$present"; then
            echo "  (absent du modèle, ignoré : $f)"
            manquants=$((manquants + 1))
            continue
        fi
        # Redirection, pas `-o` : `gh api` n'a pas ce drapeau, il n'apparaît
        # nulle part dans `gh api --help`. L'appel echouait sur « unknown flag:
        # -o », ce qui, sous `set -euo pipefail`, tuait la commande.
        mkdir -p "$(dirname "$f")"
        gh api "repos/$GITHUB_ORG/$TEMPLATE_REPO/contents/$f" \
            -H "Accept: application/vnd.github.raw" > "$f"
    done

    if (( manquants == ${#TEMPLATE_FICHIERS[@]} )); then
        echo "Erreur : le modèle $GITHUB_ORG/$TEMPLATE_REPO ne contient aucun" >&2
        echo "des fichiers attendus. Préviens ton prof." >&2
        exit 1
    fi

    exiger_uv
    uv sync

    # Couleurs neutralisées hors terminal (pipe, fichier, journal).
    local ROUGE JAUNE FIN
    if [[ -t 1 ]]; then ROUGE=$'\033[1;31m'; JAUNE=$'\033[1;33m'; FIN=$'\033[0m'
    else ROUGE=""; JAUNE=""; FIN=""; fi

    echo ""
    echo "${ROUGE}ATTENTION, tes dépendances ont été réinitialisées${FIN}"
    echo ""
    echo "${JAUNE}pyproject.toml a été remplacé par la version du prof.${FIN}"
    echo "Tous les paquets que tu avais ajoutés avec ${JAUNE}uv add${FIN} ont disparu."
    echo ""
    echo "Tu n'as rien à retrouver maintenant : reprends tes exercices normalement."
    echo "Tu verras tout de suite lesquels réinstaller, quand :"
    echo "  - Python affichera ${ROUGE}ModuleNotFoundError${FIN} à l'exécution ;"
    echo "  - ou Pylance soulignera l'import en rouge dans VSCode."
    echo ""
    echo "Dans ce cas : ${JAUNE}uv add nom_du_paquet${FIN}"
    echo ""
}

# --- update ---

cmd_update() {
    echo "Mise à jour de nsi..."
    mkdir -p "$(dirname "$INSTALL_PATH")"
    # On télécharge à côté puis on renomme : écraser le fichier pendant que
    # bash est encore en train de le lire lui ferait exécuter n'importe quoi.
    # Le mktemp est dans le même dossier, donc le mv est un simple renommage.
    local tmp
    tmp="$(mktemp "${INSTALL_PATH}.XXXXXX")"
    curl -fsSL "$GITHUB_RAW_URL" -o "$tmp"
    chmod +x "$tmp"
    mv "$tmp" "$INSTALL_PATH"
    echo "nsi mis à jour."
    exit 0
}

# --- push / pull ---

memoriser_dossier() {
    mkdir -p "$ETAT_DIR"
    printf '%s\n' "$1" > "$ETAT_DOSSIER"
}

# Le chemin mémorisé, s'il désigne toujours un dépôt git. Rend 1 sinon : le
# dossier a pu être renommé, déplacé ou supprimé à la main.
dossier_eleve() {
    [[ -f "$ETAT_DOSSIER" ]] || return 1
    local d
    d="$(cat "$ETAT_DOSSIER")"
    [[ -n "$d" && -d "$d/.git" ]] || return 1
    printf '%s\n' "$d"
}

# Se placer dans le dépôt de l'élève avant d'agir. Sans ça, `nsi push` lancé
# depuis ~ fait `git add -A` sur le dossier personnel, et `nsi reset-config`
# y déverse .vscode/, pyproject.toml et .gitignore.
aller_dans_le_depot() {
    local d
    if ! d="$(dossier_eleve)"; then
        echo "Je ne sais pas où est ton dépôt de cours." >&2
        echo "Lance d'abord : nsi init" >&2
        exit 1
    fi
    cd "$d" || exit 1
}

# Imprime le dossier de cours de l'élève, et rien d'autre : c'est la seule
# commande de nsi faite pour être composée, `code "$(nsi dir)"`. Les scripts
# d'amorçage l'utilisent plutôt que de lire $ETAT_DOSSIER, dont le chemin et le
# format ne regardent que nsi.
cmd_dir() {
    local d
    if ! d="$(dossier_eleve)"; then
        echo "Je ne sais pas où est ton dépôt de cours." >&2
        echo "Lance d'abord : nsi init" >&2
        exit 1
    fi
    printf '%s\n' "$d"
}

cmd_push() {
    aller_dans_le_depot
    git add -A
    git commit -m "Sauvegarde du $(date '+%Y-%m-%d %H:%M')" || true
    git push
}

cmd_pull() {
    aller_dans_le_depot
    git pull
}

# --- git ---

cmd_init() {
    if [[ "$(id -u)" -eq 0 ]]; then
        echo "Erreur : 'nsi init' ne doit pas être lancé avec sudo." >&2
        echo "Lance simplement : nsi init" >&2
        exit 1
    fi
    echo ""
    echo "Configuration de Git et GitHub"
    echo "=============================="
    echo ""

    # On boucle jusqu'à ce que gh accepte le jeton. Un débutant se trompe de
    # portée, colle un jeton tronqué ou expiré : lui rendre la main plutôt que
    # de le laisser devant un script mort.
    #
    # `read` qui échoue interrompt la boucle : sans terminal il rend EOF
    # immédiatement, et on tournerait sans fin sans que personne ne puisse
    # répondre.
    local github_token
    while true; do
        echo "Il te faut un token d'accès personnel GitHub."
        echo "Pour en créer un :"
        echo "  1. Va sur https://github.com/settings/tokens"
        echo "  2. Clique sur 'Generate new token (classic)'"
        echo "  3. Donne-lui un nom (ex: 'NSI') et coche les portées 'repo',"
        echo "     'read:org' et 'gist'"
        echo "  4. Clique sur 'Generate token' et copie-le IMMEDIATEMENT
     ATTENTION : le token ne s'affiche qu'une seule fois, il sera impossible de le retrouver ensuite !"
        echo ""
        if ! read -rp "Token GitHub : " github_token; then
            echo "" >&2
            echo "Erreur : impossible de lire ta réponse (pas de terminal)." >&2
            echo "Ouvre un terminal et lance : nsi init" >&2
            exit 1
        fi

        if [[ -z "$github_token" ]]; then
            echo ""
            echo "Tu n'as rien collé. On recommence."
            echo ""
            continue
        fi

        if printf '%s\n' "$github_token" | gh auth login --with-token; then
            break
        fi

        echo ""
        echo "Ce token n'a pas été accepté. Les causes les plus fréquentes :"
        echo "  - il manque une portée : il faut 'repo', 'read:org' ET 'gist'"
        echo "  - le token a été mal collé, ou tronqué"
        echo "  - il a expiré, ou tu l'as révoqué"
        echo ""
        echo "Crée-en un nouveau et recommence."
        echo ""
    done

    # Idempotent, et hors du test : `gh auth login` n'authentifie que `gh`,
    # pas `git`. Sans cet enregistrement de `gh` comme credential helper,
    # `nsi push` et `nsi pull` ne seraient pas authentifiés.
    gh auth setup-git

    local pseudo
    pseudo="$(gh api user --jq .login)"

    git config --global user.name  "$pseudo"
    git config --global user.email "${pseudo}@users.noreply.github.com"

    # Le dépôt de l'élève se déduit de ses dépôts, pas d'un calendrier.
    #
    # On demandait l'équipe de l'année scolaire en cours, calculée avec une
    # bascule au 1er août. Trois défauts : l'élève échouait net si sa classe
    # était créée un peu en avance ou en retard sur ce calendrier, les noms
    # d'équipe ne se trient pas (une vieille "Term2425" ne finit même pas par
    # une année), et l'appel à /user/teams imposait la portée `read:org` au
    # jeton pour nos propres besoins.
    #
    # `read:org` reste pourtant à cocher, mais pour une autre raison :
    # `gh auth login --with-token` l'exige pour lui-même, avec `repo` et
    # `gist`. Son aide le dit : « The minimum required scopes for the token
    # are: repo, read:org, and gist. » Un jeton sans elle est refusé par gh sur
    # « missing required scope read:org ». Ne pas la retirer de la consigne en
    # croyant qu'elle ne sert plus.
    #
    # On liste donc ses dépôts. La documentation de `affiliation` est explicite
    # sur ce qu'on y trouve : `collaborator` désigne « repositories that the
    # user has been added to as a collaborator », et c'est exactement ainsi que
    # le prof lui donne accès au sien. La valeur par défaut du paramètre
    # l'inclut déjà.
    #
    # Le filtre sur <classe>_<AAAA-AAAA>-<pseudo> écarte ce qui ne vient pas de
    # cette convention, les vieux dépôts GitHub Classroom, par exemple, et le
    # tri par date de création donne le plus récent, donc celui de cette année.
    # Le filtrage se fait en shell, pas en jq : `gh api --jq` n'accepte pas
    # `--arg`, il n'y en a aucun dans `gh api --help`, donc on ne peut pas
    # lui passer $pseudo, et `jq` n'est pas installé par `nsi install base`.
    # C'est d'ailleurs ce `--arg` qui cassait la recherche d'équipe : avec
    # `set -euo pipefail`, nsi init mourait sur « unknown flag: --arg ».
    #
    # awk plutôt que grep : il rend 0 même sans correspondance, là où un grep
    # muet ferait échouer l'affectation sous `pipefail`. Et les classes de
    # chiffres sont écrites en clair, les intervalles {4} n'étant pas garantis
    # par tous les awk.
    local depots repo_name equipe motif
    motif="^${GITHUB_ORG}/[A-Za-z0-9._-]+_[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]-${pseudo//./\\.}$"

    # On boucle jusqu'à trouver le dépôt. Accepter une invitation prend dix
    # secondes : autant laisser l'élève le faire et réessayer, plutôt que de
    # l'obliger à relancer toute l'installation.
    while true; do
        depots="$(gh api "/user/repos?per_page=100" --paginate \
            --jq '.[] | [.created_at, .full_name] | @tsv' \
            | awk -v motif="$motif" '$2 ~ motif' | sort -r)"
        [[ -n "$depots" ]] && break

        echo ""
        echo "Aucun dépôt de cours trouvé pour $pseudo dans $GITHUB_ORG."
        echo ""
        echo "Le plus souvent, c'est qu'il reste des invitations à accepter."
        echo "Connecte-toi sur GitHub avec le compte $pseudo, puis :"
        echo ""
        echo "  1. accepte l'invitation à l'organisation :"
        echo "     https://github.com/orgs/$GITHUB_ORG/invitation"
        echo "  2. accepte ensuite celle de ton dépôt : elle apparaît sur"
        echo "     https://github.com/notifications, ou dans tes courriels."
        echo ""
        echo "Si rien n'y fait, ton prof n'a pas encore mis en place ta classe :"
        echo "demande-lui."
        echo ""

        if ! read -rp "Appuie sur Entrée quand c'est fait (Ctrl+C pour abandonner) "; then
            echo "" >&2
            echo "Erreur : impossible de lire ta réponse (pas de terminal)." >&2
            exit 1
        fi
    done

    repo_name="$(head -n1 <<< "$depots" | cut -f2)"
    repo_name="${repo_name#"$GITHUB_ORG/"}"
    # L'équipe est le nom du dépôt privé de son suffixe : elle donne le nom du
    # dossier local, distinct d'une année sur l'autre.
    equipe="${repo_name%-"$pseudo"}"

    local dossier="$HOME/${equipe:?}"

    # On ne supprime jamais le dossier de l'élève. C'est pourtant ce que faisait
    # `nsi init` : il commençait par un `rm -rf`, si bien que relancer la commande
    #, ce qu'on lui dit de faire au moindre souci de jeton, effaçait tout ce
    # qui n'était pas encore poussé. Le `:?` sur $equipe est la ceinture : vide,
    # le chemin aurait désigné le dossier personnel tout entier.
    if [[ -d "$dossier/.git" ]]; then
        echo "Dossier déjà présent : ~/$equipe (rien n'est effacé)."
    elif [[ -e "$dossier" ]]; then
        echo "Erreur : ~/$equipe existe déjà et n'est pas un dépôt git." >&2
        echo "Renomme-le ou déplace-le, puis relance 'nsi init'." >&2
        exit 1
    else
        echo "Dépôt $repo_name trouvé. Récupération en local..."
        gh repo clone "$GITHUB_ORG/$repo_name" "$dossier"
    fi

    # Mémorisé seulement si le dossier existe pour de bon : un clone échoué
    # laisserait sinon un chemin mensonger dans l'état, et `nsi push` irait
    # chercher un dépôt qui n'est pas là.
    if [[ -d "$dossier/.git" ]]; then
        memoriser_dossier "$dossier"
    fi

    # Rien à déployer : les fichiers de configuration viennent du dépôt
    # template, dont le dépôt de l'élève est issu. On n'écrase jamais son
    # travail ici ; c'est `nsi reset-config` qui remet ces fichiers à neuf.
    cd "$dossier"
    exiger_uv
    uv sync

    # Pas d'ouverture de VSCode ici : lancer un éditeur est une commodité
    # d'amorçage, pas le travail de cette commande. C'est `setup.sh` qui s'en
    # charge, une fois, à la fin de l'installation.
    echo ""
    echo "Git et GitHub configurés pour $pseudo."
    echo "Dépôt : $repo_name ,  Dossier : ~/$equipe"
}

# --- auto-install si lancé hors de $INSTALL_PATH ---

SELF="$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")"
if [[ "$SELF" != "$INSTALL_PATH" ]]; then
    echo "Installation de nsi dans $INSTALL_PATH..."
    mkdir -p "$(dirname "$INSTALL_PATH")"
    _tmp="$(mktemp "${INSTALL_PATH}.XXXXXX")"
    curl -fsSL "$GITHUB_RAW_URL" -o "$_tmp"
    chmod +x "$_tmp"
    mv "$_tmp" "$INSTALL_PATH"
    exec "$INSTALL_PATH" "$@"
fi

# --- Dispatch ---

# Sur macOS, Homebrew refuse d'être lancé en root (ensure_brew et tous les
# "brew install" plus haut échoueraient) : nsi ne doit donc jamais être
# invoqué avec sudo là-bas. Chaque commande élève elle-même les privilèges
# dont elle a besoin (apt/dnf), rien de plus n'est requis ailleurs non plus.
if is_mac && [[ "$(id -u)" -eq 0 ]]; then
    echo "Ne lance pas nsi avec sudo sur macOS : Homebrew le refuse." >&2
    echo "Lance simplement : nsi $*" >&2
    exit 1
fi

cmd="${1:-}"
component="${2:-}"

case "$cmd" in
    install)
        case "$component" in
            base)       install_base ;;
            gleam)      install_gleam ;;
            postgresql) install_postgresql ;;
            openjdk)    install_openjdk ;;
            nasm)       install_nasm ;;
            rust)       install_rust ;;
            prolog)     install_prolog ;;
            c)          install_c ;;
            *) echo "Composant inconnu: $component" >&2; exit 1 ;;
        esac
        ;;
    remove)
        case "$component" in
            base)       remove_base ;;
            gleam)      remove_gleam ;;
            postgresql) remove_postgresql ;;
            openjdk)    remove_openjdk ;;
            nasm)       remove_nasm ;;
            rust)       remove_rust ;;
            prolog)     remove_prolog ;;
            c)          remove_c ;;
            *) echo "Composant inconnu: $component" >&2; exit 1 ;;
        esac
        ;;
    update)
        cmd_update
        ;;
    init)
        cmd_init
        ;;
    dir)
        cmd_dir
        ;;
    push)
        cmd_push
        ;;
    pull)
        cmd_pull
        ;;
    reset-config)
        cmd_reset_config
        ;;
    toggle-config)
        cmd_toggle_config
        ;;
    *)
        echo "Usage: nsi install|remove base|gleam|postgresql|openjdk|nasm|rust|prolog|c" >&2
        echo "       nsi update" >&2
        echo "       nsi init" >&2
        echo "       nsi push | nsi pull" >&2
        echo "       nsi dir" >&2
        echo "       nsi reset-config" >&2
        echo "       nsi toggle-config" >&2
        exit 1
        ;;
esac
