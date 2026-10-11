#!/usr/bin/env bash
# Installs / removes the programs listed in the README on Arch Linux.
# Usage: ./install-arch.sh [-y]
#   -y   Don't ask for confirmation per package (answer "yes" to everything)

set -uo pipefail
USER=${USER:-$(id -un)}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

AUTO_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) AUTO_YES=1 ;;
        -h|--help)
            echo "Usage: $0 [-y]"
            echo "  -y   Don't ask for confirmation per package"
            exit 0 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

if [[ -t 1 ]]; then
    C_BLUE=$'\e[1;34m'; C_GREEN=$'\e[1;32m'; C_YELLOW=$'\e[1;33m'; C_RED=$'\e[1;31m'; C_RESET=$'\e[0m'
else
    C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi
info()  { echo "${C_BLUE}::${C_RESET} $*"; }
ok()    { echo "${C_GREEN}==>${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}==> WARNING:${C_RESET} $*"; }
err()   { echo "${C_RED}==> ERROR:${C_RESET} $*"; }

# ask "question" [default y|n] -> 0 = yes, 1 = no
ask() {
    local question=$1 default=${2:-y} hint answer
    if (( AUTO_YES )); then
        echo "${C_BLUE}::${C_RESET} $question [auto: y]"
        return 0
    fi
    [[ $default == y ]] && hint="[Y/n]" || hint="[y/N]"
    while true; do
        read -r -p "${C_BLUE}::${C_RESET} $question $hint " answer
        answer=${answer,,}
        [[ -z $answer ]] && answer=$default
        case "$answer" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
        esac
    done
}

ITEMS=(
    "Main;Zen-Browser;zen-browser-bin/zen-browser;"
    "Main;Only Office;onlyoffice-bin/onlyoffice;"
    "Main;Spotify;spotify-launcher/spotify;"
    "Main;VSCodium;vscodium-bin/vscodium/code/visual-studio-code-bin;"
    "Main;VM (QEMU/KVM + virt-manager);virt-manager qemu-full libvirt dnsmasq;"
    "Main;WhatsApp;wasistlos/zapzap/whatsapp-for-linux;"
    "Main;Input Remapper;input-remapper-git/input-remapper-bin/input-remapper;"
    "Main;Git Login (git + GitHub CLI);git github-cli;noremove"
    "Main;Pipewire;pipewire pipewire-pulse pipewire-alsa wireplumber;noremove"
    "Main;Screensharing;xdg-desktop-portal @PORTAL@;noremove"
    "Lab;Docker;docker docker-compose docker-buildx;"
    "Lab;Tailscale;tailscale;"
    "Game;Swiftpoint Control Center;;unsupported"
    "Game;Steam;steam;"
    "Game;Discord;discord;"
    "Game;Minecraft Launcher;minecraft-launcher;"
    "Game;Prism Launcher;prismlauncher;"
    "Game;Heroic Games Launcher;heroic-games-launcher-bin/heroic-games-launcher;"
    "School;wxMaxima;wxmaxima;"
    "School;IntelliJ IDEA;intellij-idea-community-edition/intellij-idea-ultimate-edition/intellij-idea-ultimate-edition-bin;"
    "School;Zotero;zotero-bin/zotero;"
    "School;SafeExam Browser;;unsupported"
)
CATEGORIES=(Main Game Lab School)

# Matching screensharing portal for the current desktop
portal_backend() {
    local de=${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}
    de=${de,,}
    case "$de" in
        *hyprland*)            echo xdg-desktop-portal-hyprland ;;
        *kde*|*plasma*)        echo xdg-desktop-portal-kde ;;
        *gnome*)               echo xdg-desktop-portal-gnome ;;
        *sway*|*river*|*wlr*)  echo xdg-desktop-portal-wlr ;;
        *)                     echo xdg-desktop-portal-gtk ;;
    esac
}

# Is a package (or something providing it) installed?
is_installed() { pacman -T "$1" &>/dev/null; }

# Does the package exist in the repos or the AUR?
pkg_exists() { pacman -Si "$1" &>/dev/null </dev/null || yay -Si "$1" &>/dev/null </dev/null; }

# Prints the package slots of an item (one line per slot)
item_slots() {
    local pkgs=${1//@PORTAL@/$(portal_backend)}
    tr ' ' '\n' <<<"$pkgs" | sed '/^$/d'
}

# Which slots are still missing? -> packages to install on stdout
missing_packages() {
    local slot alt chosen found
    while read -r slot; do
        found=0
        IFS='/' read -ra alts <<<"$slot"
        for alt in "${alts[@]}"; do
            if is_installed "$alt"; then found=1; break; fi
        done
        (( found )) && continue
        chosen=""
        for alt in "${alts[@]}"; do
            if pkg_exists "$alt"; then chosen=$alt; break; fi
        done
        if [[ -n $chosen ]]; then
            echo "$chosen"
        else
            echo "!${alts[0]}"   # not found
        fi
    done < <(item_slots "$1")
}

# Installed packages of an item (for removal)
installed_packages() {
    local slot alt
    while read -r slot; do
        IFS='/' read -ra alts <<<"$slot"
        for alt in "${alts[@]}"; do
            pacman -Qq "$alt" &>/dev/null && echo "$alt"
        done
    done < <(item_slots "$1")
}

yay_install() {
    yay -S --needed --noconfirm \
        --answerclean None --answerdiff None --answeredit None --removemake \
        "$@"
}

ensure_yay() {
    command -v yay &>/dev/null && return 0
    warn "yay is not installed."
    if ! ask "Install yay now?"; then
        err "AUR packages can't be installed without yay. Aborting."
        exit 1
    fi
    sudo pacman -S --needed --noconfirm git base-devel || { err "Could not install git/base-devel."; exit 1; }
    local tmp
    tmp=$(mktemp -d)
    git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" \
        && (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
    command -v yay &>/dev/null || { err "yay installation failed."; exit 1; }
    ok "yay installed."
}

ensure_multilib() {
    grep -q '^\[multilib\]' /etc/pacman.conf 2>/dev/null && return 0
    warn "The multilib repository is disabled (required for Steam)."
    ask "Enable multilib in /etc/pacman.conf and update the system?" || return 1
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    sudo pacman -Syu --noconfirm
}

# pipewire-pulse conflicts with pulseaudio -> remove it first
resolve_pipewire_conflicts() {
    local old=() p
    for p in pulseaudio pulseaudio-bluetooth pulseaudio-alsa; do
        pacman -Qq "$p" &>/dev/null && old+=("$p")
    done
    (( ${#old[@]} )) || return 0
    warn "Conflict: ${old[*]} must be removed for pipewire-pulse."
    ask "Remove ${old[*]}?" || return 1
    sudo pacman -Rdd --noconfirm "${old[@]}"
}

add_user_to_group() {
    local group=$1
    id -nG "$USER" | tr ' ' '\n' | grep -qx "$group" && return 0
    sudo usermod -aG "$group" "$USER" && info "Added $USER to group '$group' (log out and back in to apply)."
}

post_install() {
    case "$1" in
        "VM (QEMU/KVM + virt-manager)")
            sudo systemctl enable --now libvirtd.service
            add_user_to_group libvirt ;;
        "Docker")
            sudo systemctl enable --now docker.service
            add_user_to_group docker ;;
        "Tailscale")
            sudo systemctl enable --now tailscaled.service
            info "Log in with 'sudo tailscale up'." ;;
    esac
}

# Copies configs/<dir> from this repo to ~/.config/<dir>.
# Returns 0 if at least one file was changed.
deploy_config() {
    local dir=$1 src dst rel changed=1
    # fd 3, so that ask can still read from the terminal
    while IFS= read -r -d '' src <&3; do
        rel=${src#"$SCRIPT_DIR/configs/$dir/"}
        dst="$HOME/.config/$dir/$rel"
        cmp -s "$src" "$dst" && continue
        if [[ -e $dst ]]; then
            ask "Overwrite ~/.config/$dir/$rel with the version from this repo?" n || continue
            cp "$dst" "$dst.bak"
        fi
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst" && info "Copied ~/.config/$dir/$rel" && changed=0
    done 3< <(find "$SCRIPT_DIR/configs/$dir" -type f -print0)
    return $changed
}

# Applies configs / logins - runs after installing and when already installed
configure_item() {
    case "$1" in
        "Input Remapper")
            sudo systemctl enable --now input-remapper.service
            deploy_config input-remapper-2 && input-remapper-control --command autoload &>/dev/null ;;
        "Pipewire")
            systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true ;;
        "Git Login (git + GitHub CLI)")
            git_setup ;;
    esac
}

git_setup() {
    local name email
    if [[ -z $(git config --global user.name) ]]; then
        if (( AUTO_YES )); then
            info "Git name not set: git config --global user.name \"Your Name\""
        else
            read -r -p "${C_BLUE}::${C_RESET} Git name: " name
            [[ -n $name ]] && git config --global user.name "$name"
        fi
    fi
    if [[ -z $(git config --global user.email) ]]; then
        if (( AUTO_YES )); then
            info "Git email not set: git config --global user.email \"you@example.com\""
        else
            read -r -p "${C_BLUE}::${C_RESET} Git email: " email
            [[ -n $email ]] && git config --global user.email "$email"
        fi
    fi
    if gh auth status &>/dev/null; then
        ok "Already logged in to GitHub."
    else
        info "Logging in to GitHub (gh auth login)..."
        gh auth login || { err "GitHub login failed."; return; }
    fi
    gh auth setup-git
}

install_item() {
    local cat name pkgs flags missing=() notfound=() p
    IFS=';' read -r cat name pkgs flags <<<"$1"

    if [[ $flags == *unsupported* ]]; then
        warn "$name is not available for Linux - skipped."
        return
    fi

    # Steam lives in multilib -> must be enabled before looking up packages
    if [[ " $pkgs " == *" steam "* ]] && ! is_installed steam; then
        ensure_multilib || { warn "Steam skipped (multilib disabled)."; return; }
    fi

    while read -r p; do
        [[ -z $p ]] && continue
        if [[ $p == !* ]]; then notfound+=("${p#!}"); else missing+=("$p"); fi
    done < <(missing_packages "$pkgs")

    if (( ${#notfound[@]} )); then
        err "$name: package(s) not found: ${notfound[*]}"
    fi
    if (( ${#missing[@]} == 0 )); then
        (( ${#notfound[@]} )) || { ok "$name is already installed."; configure_item "$name"; }
        return
    fi

    ask "Install $name? (${missing[*]})" || return

    [[ " ${missing[*]} " == *" pipewire-pulse "* ]] && { resolve_pipewire_conflicts || { warn "Pipewire skipped."; return; }; }

    if yay_install "${missing[@]}"; then
        ok "$name installed."
        post_install "$name"
        configure_item "$name"
    else
        err "$name could not be installed."
    fi
}

remove_item() {
    local cat name pkgs flags installed=()
    IFS=';' read -r cat name pkgs flags <<<"$1"

    [[ $flags == *unsupported* ]] && return
    if [[ $flags == *noremove* ]]; then
        info "$name is a system component - not removed."
        return
    fi

    mapfile -t installed < <(installed_packages "$pkgs")
    if (( ${#installed[@]} == 0 )); then
        info "$name is not installed."
        return
    fi

    ask "Remove $name? (${installed[*]})" n || return
    if yay -Rns --noconfirm "${installed[@]}"; then
        ok "$name removed."
    else
        err "$name could not be removed."
    fi
}

run_for_categories() {
    local action=$1; shift
    local cat item
    for cat in "$@"; do
        echo
        echo "${C_GREEN}===== $cat =====${C_RESET}"
        for item in "${ITEMS[@]}"; do
            [[ ${item%%;*} == "$cat" ]] || continue
            "$action" "$item"
        done
    done
}

choose_categories() {
    local input n selected=()
    echo "Categories:" >&2
    for n in "${!CATEGORIES[@]}"; do
        echo "  $((n + 1)) ${CATEGORIES[$n]}" >&2
    done
    while (( ${#selected[@]} == 0 )); do
        read -r -p "Selection (e.g. 1 3): " input
        for n in ${input//,/ }; do
            if [[ $n =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#CATEGORIES[@]} )); then
                selected+=("${CATEGORIES[$((n - 1))]}")
            else
                echo "Invalid: $n" >&2
            fi
        done
    done
    printf '%s\n' "${selected[@]}" | awk '!seen[$0]++'
}

if (( EUID == 0 )); then
    err "Don't run this as root (yay/makepkg refuse to run as root). sudo is used when needed."
    exit 1
fi
if ! command -v pacman &>/dev/null; then
    err "pacman not found - this script is for Arch Linux only."
    exit 1
fi

echo "What do you want to do?"
echo "  1 Install everything"
echo "  2 Install selected categories"
echo "  3 Remove selected categories"
echo "  4 Cancel"
read -r -p "Selection [1-4]: " choice

case "$choice" in
    1)
        ensure_yay
        sudo -v
        run_for_categories install_item "${CATEGORIES[@]}" ;;
    2)
        mapfile -t cats < <(choose_categories)
        ensure_yay
        sudo -v
        run_for_categories install_item "${cats[@]}" ;;
    3)
        mapfile -t cats < <(choose_categories)
        ensure_yay
        sudo -v
        run_for_categories remove_item "${cats[@]}" ;;
    *)
        echo "Cancelled."
        exit 0 ;;
esac

echo
ok "Done."
