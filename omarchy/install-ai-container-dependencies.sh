#!/usr/bin/env bash
# Package prerequisites only. Runtime registration and activation are separate.
set -euo pipefail

ai_container_usage() {
    cat <<'EOF'
Usage: bash omarchy/install-ai-container-dependencies.sh [--check | --install] [--yes]

Default: read-only package and NVIDIA driver check (exit 2 if not ready).
--install  Install missing packages from existing pacman indexes.
--yes      Accept the package transaction without its interactive confirmation.
--help     Show this help.

For Arch/Omarchy x86_64 with a working NVIDIA driver. Packages: docker,
docker-compose, nvidia-container-toolkit. Does not refresh package indexes,
upgrade the OS, install GPU drivers, change Docker configuration, start/restart
services, add users to groups, install Dokploy, or download images/models.
EOF
}

ai_container_main() {
    local mode=check assume_yes=false option package pending query_rc driver_ready=true
    local -a packages=(docker docker-compose nvidia-container-toolkit)
    local -a missing=() privilege=() confirmation=()
    for option in "$@"; do
        case "$option" in
            --check) mode=check ;;
            --install) mode=install ;;
            --yes) assume_yes=true ;;
            --help|-h) ai_container_usage; return 0 ;;
            *) printf 'Unknown option: %s\n' "$option" >&2; return 1 ;;
        esac
    done
    if $assume_yes && [[ $mode != install ]]; then
        printf '%s\n' '--yes requires --install.' >&2
        return 1
    fi
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 && -r /etc/arch-release ]] || {
        printf '%s\n' 'This installer requires Arch/Omarchy Linux on x86_64.' >&2
        return 1
    }
    command -v pacman >/dev/null || {
        printf '%s\n' 'pacman is required.' >&2
        return 1
    }
    for package in "${packages[@]}"; do
        if ! pacman -Q "$package" >/dev/null 2>&1; then
            missing+=("$package")
        fi
    done
    if ! command -v nvidia-smi >/dev/null ||
        ! nvidia-smi --query-gpu=name --format=csv,noheader; then
        driver_ready=false
        printf '%s\n' 'A working NVIDIA host driver is required. Repair it through the normal Omarchy procedure.' >&2
    fi
    if ((${#missing[@]})); then
        printf 'Missing packages:\n'
        printf '  %s\n' "${missing[@]}"
    fi
    $driver_ready || return 2
    if ((${#missing[@]} == 0)); then
        pacman -Q "${packages[@]}"
        printf '%s\n' 'Packages and host driver are present. Docker GPU access still needs runtime verification.'
        return 0
    fi
    [[ $mode == install ]] || return 2

    # Never create a partial upgrade or silently upgrade the operating system.
    query_rc=0
    pending=$(pacman -Qu 2>&1) || query_rc=$?
    if ((query_rc > 1)) || { ((query_rc != 0)) && [[ -n $pending ]]; }; then
        printf '%s\n' 'Could not inspect pending upgrades. Diagnose pacman -Qu before installing.' >&2
        return 1
    fi
    if [[ -n $pending ]]; then
        printf '%s\n' 'Pending upgrades exist. Complete the normal Omarchy system update first.' >&2
        return 1
    fi
    pacman -Sp --needed --print-format '%n %v' "${missing[@]}" || return
    if ((EUID != 0)); then
        command -v sudo >/dev/null || {
            printf '%s\n' 'Run with sudo, or install sudo using your normal system procedure.' >&2
            return 1
        }
        privilege=(sudo)
    fi
    $assume_yes && confirmation=(--noconfirm)
    "${privilege[@]}" pacman -S --needed "${confirmation[@]}" -- "${missing[@]}" || return
    pacman -Q "${packages[@]}" || return
    printf '%s\n' 'Packages installed. Follow the README to register and verify the NVIDIA Docker runtime.'
}

if [[ ${BASH_SOURCE[0]:-$0} == "$0" ]]; then
    ai_container_main "$@"
fi
