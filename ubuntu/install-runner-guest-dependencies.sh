#!/usr/bin/env bash
# Guest OS prerequisites only. Does not enroll or start CI runners.
set -euo pipefail

runner_guest_usage() {
    cat <<'EOF'
Usage: bash ubuntu/install-runner-guest-dependencies.sh [--check | --install] [--yes]

Default: check prerequisites without changing the machine (exit 2 if missing).
--install  Refresh apt indexes and install missing packages without recommends.
--yes      Accept the package transaction without its interactive confirmation.
--help     Show this help.

For a dedicated Ubuntu 24.04 amd64 VM running systemd. Package maintainer
scripts may start services. Runner, firewall, user and credential setup is separate.
EOF
}

runner_guest_platform() {
    [[ $(uname -s) == Linux && -r /etc/os-release ]] || {
        printf '%s\n' 'This installer requires an Ubuntu 24.04 Linux guest.' >&2
        return 1
    }
    local ID='' VERSION_ID=''
    # shellcheck source=/dev/null
    . /etc/os-release
    [[ $ID == ubuntu && $VERSION_ID == 24.04 ]] || {
        printf '%s\n' 'Only Ubuntu 24.04 is supported.' >&2
        return 1
    }
    local tool
    for tool in apt-get dpkg dpkg-query systemd-detect-virt; do
        command -v "$tool" >/dev/null || {
            printf 'Required command is missing: %s\n' "$tool" >&2
            return 1
        }
    done
    [[ $(dpkg --print-architecture) == amd64 && -d /run/systemd/system ]] || {
        printf '%s\n' 'The guest must be amd64 and running systemd.' >&2
        return 1
    }
    systemd-detect-virt --vm --quiet || {
        printf '%s\n' 'Run this only inside the dedicated VM, not on a host or in a container.' >&2
        return 1
    }
}

runner_guest_main() {
    local mode=check assume_yes=false option package package_state
    local -a packages=(podman qemu-guest-agent catatonit jq curl nftables python3-cryptography)
    local -a missing=() privilege=() confirmation=()
    for option in "$@"; do
        case "$option" in
            --check) mode=check ;;
            --install) mode=install ;;
            --yes) assume_yes=true ;;
            --help|-h) runner_guest_usage; return 0 ;;
            *) printf 'Unknown option: %s\n' "$option" >&2; return 1 ;;
        esac
    done
    if $assume_yes && [[ $mode != install ]]; then
        printf '%s\n' '--yes requires --install.' >&2
        return 1
    fi
    runner_guest_platform || return
    for package in "${packages[@]}"; do
        package_state=$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null) || package_state=''
        [[ $package_state == 'ii ' ]] || missing+=("$package")
    done
    if ((${#missing[@]} == 0)); then
        printf '%s\n' 'All runner guest prerequisites are installed.'
        dpkg-query -W -f='${binary:Package} ${Version}\n' "${packages[@]}"
        return
    fi
    printf 'Missing packages:\n'
    printf '  %s\n' "${missing[@]}"
    [[ $mode == install ]] || return 2
    if ((EUID != 0)); then
        command -v sudo >/dev/null || {
            printf '%s\n' 'Run with sudo, or install sudo using your normal system procedure.' >&2
            return 1
        }
        privilege=(sudo)
    fi
    $assume_yes && confirmation=(-y)
    "${privilege[@]}" apt-get update || return
    "${privilege[@]}" apt-get install --no-install-recommends --no-remove "${confirmation[@]}" -- "${missing[@]}" || return
    for package in "${packages[@]}"; do
        package_state=$(dpkg-query -W -f='${db:Status-Abbrev}' "$package") || return
        [[ $package_state == 'ii ' ]] || {
            printf 'Package is not configured: %s\n' "$package" >&2
            return 1
        }
    done
    dpkg-query -W -f='${binary:Package} ${Version}\n' "${packages[@]}" || return
    printf '%s\n' 'Dependencies installed. Configure guest protection and runner units separately.'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    runner_guest_main "$@"
fi
