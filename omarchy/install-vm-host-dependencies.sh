#!/usr/bin/env bash
# Package prerequisites only. VM, network and service configuration is separate.
set -euo pipefail

vm_host_usage() {
    cat <<'EOF'
Usage: bash omarchy/install-vm-host-dependencies.sh [--check | --install] [--yes]

Default: check package prerequisites without changing the machine (exit 2 if missing).
--install  Install missing packages from the existing pacman indexes.
--yes      Accept the package transaction without its interactive confirmation.
--help     Show this help.

For Arch/Omarchy x86_64. Does not refresh indexes, upgrade the OS, configure
libvirt, enable services, create VMs/networks, or change user permissions.
EOF
}

vm_host_platform() {
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
        printf '%s\n' 'This installer requires Arch/Omarchy Linux on x86_64.' >&2
        return 1
    }
    [[ -r /etc/arch-release ]] || {
        printf '%s\n' 'Arch Linux was not detected.' >&2
        return 1
    }
    command -v pacman >/dev/null || {
        printf '%s\n' 'pacman is required.' >&2
        return 1
    }
}

vm_host_main() {
    local mode=check assume_yes=false option package pending query_rc
    local -a packages=(qemu-base libvirt dnsmasq edk2-ovmf cloud-image-utils
                       nftables curl gnupg python jq)
    local -a missing=() privilege=() confirmation=()
    for option in "$@"; do
        case "$option" in
            --check) mode=check ;;
            --install) mode=install ;;
            --yes) assume_yes=true ;;
            --help|-h) vm_host_usage; return 0 ;;
            *) printf 'Unknown option: %s\n' "$option" >&2; return 1 ;;
        esac
    done
    if $assume_yes && [[ $mode != install ]]; then
        printf '%s\n' '--yes requires --install.' >&2
        return 1
    fi
    vm_host_platform || return
    for package in "${packages[@]}"; do
        if ! pacman -Q "$package" >/dev/null 2>&1; then
            missing+=("$package")
        fi
    done
    if ((${#missing[@]} == 0)); then
        printf '%s\n' 'All VM host prerequisites are installed.'
        pacman -Q "${packages[@]}"
        return
    fi
    printf 'Missing packages:\n'
    printf '  %s\n' "${missing[@]}"
    [[ $mode == install ]] || return 2

    # Installing against indexes from a partial upgrade is unsafe. Never refresh
    # them here or silently turn a prerequisite install into an OS upgrade.
    query_rc=0
    pending=$(pacman -Qu 2>&1) || query_rc=$?
    if ((query_rc != 0)) && [[ -n $pending ]]; then
        printf '%s\n' 'Could not inspect pending upgrades; run pacman -Qu to diagnose before installing.' >&2
        return 1
    fi
    if [[ -n $pending ]]; then
        printf '%s\n' 'Pending upgrades exist in the current indexes. Complete the normal system update first.' >&2
        return 1
    fi
    if ((query_rc > 1)); then
        printf '%s\n' 'Could not inspect pending upgrades; installation stopped.' >&2
        return 1
    fi
    # Print and resolve the whole transaction before requesting privilege.
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
    printf '%s\n' 'Dependencies installed. Configure protected networking and libvirt separately before starting a VM.'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    vm_host_main "$@"
fi
