#!/usr/bin/env bash
# Installiert / entfernt die Programme aus der README auf Arch Linux.
# Nutzung: bash install-arch.sh [-y]
#   -y   Keine Rückfragen pro Paket (alles mit "ja" beantworten)

set -uo pipefail
USER=${USER:-$(id -un)}

AUTO_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) AUTO_YES=1 ;;
        -h|--help)
            echo "Nutzung: $0 [-y]"
            echo "  -y   Keine Rückfragen pro Paket"
            exit 0 ;;
        *) echo "Unbekannte Option: $arg"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Farben / Ausgabe
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_BLUE=$'\e[1;34m'; C_GREEN=$'\e[1;32m'; C_YELLOW=$'\e[1;33m'; C_RED=$'\e[1;31m'; C_RESET=$'\e[0m'
else
    C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi
info()  { echo "${C_BLUE}::${C_RESET} $*"; }
ok()    { echo "${C_GREEN}==>${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}==> WARNUNG:${C_RESET} $*"; }
err()   { echo "${C_RED}==> FEHLER:${C_RESET} $*"; }

# ask "Frage" [default y|n] -> 0 = ja, 1 = nein
ask() {
    local question=$1 default=${2:-y} hint answer
    if (( AUTO_YES )); then
        echo "${C_BLUE}::${C_RESET} $question [automatisch: j]"
        return 0
    fi
    [[ $default == y ]] && hint="[J/n]" || hint="[j/N]"
    while true; do
        read -r -p "${C_BLUE}::${C_RESET} $question $hint " answer
        answer=${answer,,}
        [[ -z $answer ]] && answer=$default
        case "$answer" in
            j|ja|y|yes) return 0 ;;
            n|nein|no)  return 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Paketliste
# Format: "Kategorie;Name;Pakete;Flags"
#   Pakete: durch Leerzeichen getrennt, Alternativen mit "/" (erste verfügbare
#           wird installiert, jede gilt als "bereits installiert")
#   Flags:  noremove  -> wird beim Löschen übersprungen (Systemkomponenten)
#           unsupported -> unter Linux nicht verfügbar
# ---------------------------------------------------------------------------
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

# Passendes Screensharing-Portal je nach Desktop
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

# ---------------------------------------------------------------------------
# Hilfsfunktionen für Pakete
# ---------------------------------------------------------------------------
# Ist ein Paket (oder etwas, das es bereitstellt) installiert?
is_installed() { pacman -T "$1" &>/dev/null; }

# Existiert das Paket in den Repos oder im AUR?
pkg_exists() { pacman -Si "$1" &>/dev/null </dev/null || yay -Si "$1" &>/dev/null </dev/null; }

# Schreibt die Paket-Slots eines Eintrags (eine Zeile pro Slot)
item_slots() {
    local pkgs=${1//@PORTAL@/$(portal_backend)}
    tr ' ' '\n' <<<"$pkgs" | sed '/^$/d'
}

# Welche Slots fehlen noch? -> zu installierende Pakete auf stdout
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
            echo "!${alts[0]}"   # nicht gefunden
        fi
    done < <(item_slots "$1")
}

# Installierte Pakete eines Eintrags (für das Löschen)
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

# ---------------------------------------------------------------------------
# Vorbereitung: yay, multilib
# ---------------------------------------------------------------------------
ensure_yay() {
    command -v yay &>/dev/null && return 0
    warn "yay ist nicht installiert."
    if ! ask "yay jetzt installieren?"; then
        err "Ohne yay können keine AUR-Pakete installiert werden. Abbruch."
        exit 1
    fi
    sudo pacman -S --needed --noconfirm git base-devel || { err "git/base-devel konnten nicht installiert werden."; exit 1; }
    local tmp
    tmp=$(mktemp -d)
    git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" \
        && (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
    command -v yay &>/dev/null || { err "yay-Installation fehlgeschlagen."; exit 1; }
    ok "yay installiert."
}

ensure_multilib() {
    grep -q '^\[multilib\]' /etc/pacman.conf 2>/dev/null && return 0
    warn "Das multilib-Repository ist deaktiviert (wird für Steam benötigt)."
    ask "multilib in /etc/pacman.conf aktivieren und System aktualisieren?" || return 1
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    sudo pacman -Syu --noconfirm
}

# Pipewire-Pulse kollidiert mit pulseaudio -> vorher entfernen
resolve_pipewire_conflicts() {
    local old=() p
    for p in pulseaudio pulseaudio-bluetooth pulseaudio-alsa; do
        pacman -Qq "$p" &>/dev/null && old+=("$p")
    done
    (( ${#old[@]} )) || return 0
    warn "Konflikt: ${old[*]} muss für pipewire-pulse entfernt werden."
    ask "${old[*]} entfernen?" || return 1
    sudo pacman -Rdd --noconfirm "${old[@]}"
}

# ---------------------------------------------------------------------------
# Nachbereitung nach der Installation
# ---------------------------------------------------------------------------
add_user_to_group() {
    local group=$1
    id -nG "$USER" | tr ' ' '\n' | grep -qx "$group" && return 0
    sudo usermod -aG "$group" "$USER" && info "$USER zur Gruppe '$group' hinzugefügt (neu anmelden nötig)."
}

post_install() {
    case "$1" in
        "VM (QEMU/KVM + virt-manager)")
            sudo systemctl enable --now libvirtd.service
            add_user_to_group libvirt ;;
        "Input Remapper")
            sudo systemctl enable --now input-remapper.service ;;
        "Docker")
            sudo systemctl enable --now docker.service
            add_user_to_group docker ;;
        "Tailscale")
            sudo systemctl enable --now tailscaled.service
            info "Mit 'sudo tailscale up' anmelden." ;;
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
            info "Git-Name nicht gesetzt: git config --global user.name \"Dein Name\""
        else
            read -r -p "${C_BLUE}::${C_RESET} Git Name: " name
            [[ -n $name ]] && git config --global user.name "$name"
        fi
    fi
    if [[ -z $(git config --global user.email) ]]; then
        if (( AUTO_YES )); then
            info "Git-E-Mail nicht gesetzt: git config --global user.email \"du@example.com\""
        else
            read -r -p "${C_BLUE}::${C_RESET} Git E-Mail: " email
            [[ -n $email ]] && git config --global user.email "$email"
        fi
    fi
    if ! gh auth status &>/dev/null; then
        if (( AUTO_YES )); then
            info "GitHub-Login später mit: gh auth login"
        elif ask "Jetzt bei GitHub anmelden (gh auth login)?"; then
            gh auth login
        fi
    fi
}

# ---------------------------------------------------------------------------
# Installieren / Löschen
# ---------------------------------------------------------------------------
install_item() {
    local cat name pkgs flags missing=() notfound=() p
    IFS=';' read -r cat name pkgs flags <<<"$1"

    if [[ $flags == *unsupported* ]]; then
        warn "$name gibt es nicht für Linux – übersprungen."
        return
    fi

    # Steam liegt in multilib -> muss vor der Paketsuche aktiv sein
    if [[ " $pkgs " == *" steam "* ]] && ! is_installed steam; then
        ensure_multilib || { warn "Steam übersprungen (multilib deaktiviert)."; return; }
    fi

    while read -r p; do
        [[ -z $p ]] && continue
        if [[ $p == !* ]]; then notfound+=("${p#!}"); else missing+=("$p"); fi
    done < <(missing_packages "$pkgs")

    if (( ${#notfound[@]} )); then
        err "$name: Paket(e) nicht gefunden: ${notfound[*]}"
    fi
    if (( ${#missing[@]} == 0 )); then
        (( ${#notfound[@]} )) || ok "$name ist bereits installiert."
        return
    fi

    ask "$name installieren? (${missing[*]})" || return

    [[ " ${missing[*]} " == *" pipewire-pulse "* ]] && { resolve_pipewire_conflicts || { warn "Pipewire übersprungen."; return; }; }

    if yay_install "${missing[@]}"; then
        ok "$name installiert."
        post_install "$name"
    else
        err "$name konnte nicht installiert werden."
    fi
}

remove_item() {
    local cat name pkgs flags installed=()
    IFS=';' read -r cat name pkgs flags <<<"$1"

    [[ $flags == *unsupported* ]] && return
    if [[ $flags == *noremove* ]]; then
        info "$name ist eine Systemkomponente – wird nicht gelöscht."
        return
    fi

    mapfile -t installed < <(installed_packages "$pkgs")
    if (( ${#installed[@]} == 0 )); then
        info "$name ist nicht installiert."
        return
    fi

    ask "$name löschen? (${installed[*]})" n || return
    if yay -Rns --noconfirm "${installed[@]}"; then
        ok "$name gelöscht."
    else
        err "$name konnte nicht gelöscht werden."
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
    echo "Kategorien:" >&2
    for n in "${!CATEGORIES[@]}"; do
        echo "  $((n + 1)) ${CATEGORIES[$n]}" >&2
    done
    while (( ${#selected[@]} == 0 )); do
        read -r -p "Auswahl (z.B. 1 3): " input
        for n in ${input//,/ }; do
            if [[ $n =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#CATEGORIES[@]} )); then
                selected+=("${CATEGORIES[$((n - 1))]}")
            else
                echo "Ungültig: $n" >&2
            fi
        done
    done
    printf '%s\n' "${selected[@]}" | awk '!seen[$0]++'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if (( EUID == 0 )); then
    err "Bitte nicht als root ausführen (yay/makepkg verweigern root). sudo wird bei Bedarf genutzt."
    exit 1
fi
if ! command -v pacman &>/dev/null; then
    err "pacman nicht gefunden – das Skript ist nur für Arch Linux."
    exit 1
fi

echo "Was möchtest du tun?"
echo "  1 Alles installieren"
echo "  2 Gewünschte Kategorien installieren"
echo "  3 Gewünschte Kategorien löschen"
echo "  4 Abbrechen"
read -r -p "Auswahl [1-4]: " choice

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
        echo "Abgebrochen."
        exit 0 ;;
esac

echo
ok "Fertig."
