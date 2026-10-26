# Omarchy preferences

Small, readable scripts for rebuilding a familiar Omarchy development laptop after a reinstall or on another machine.

## Remote development

Run [`configure-remote-development.sh`](configure-remote-development.sh) to apply these preferences:

| Setting | Result |
| --- | --- |
| Idle screen lock | Disabled |
| Idle screensaver | Disabled |
| Close the lid while plugged in | Stay awake and unlocked |
| Close the lid on battery | Keep the existing battery suspend policy and Omarchy lid handler |
| Manual lock and lock before sleep | Keep the existing behavior |
| Displays when opening or closing the lid | Keep Omarchy's monitor handling |

These preferences intentionally leave the desktop accessible when unattended. Lock it manually when needed. The AC exception applies when the lid closes; unplugging an already closed laptop is a separate power event.

### Install

This targets **Omarchy 4's Lua Hyprland configuration and Quickshell idle service**. It needs the existing `shell.json`, `bindings.lua`, Omarchy lid/monitor commands, Python 3, `luac`, and a reloadable `systemd-logind`. It does not target older `hyprland.conf`/`hypridle.conf` installations.

From an active terminal in the Omarchy desktop:

```bash
git clone https://github.com/lmachineone/bash-scripts.git
cd bash-scripts
bash omarchy/configure-remote-development.sh
```

If the repository is already checked out, run the last command from its root. Run it as your normal user. Enter the administrator password only at the local `sudo` prompt.

The script changes only the two idle values, a marked personal lid binding, its helper, and one logind drop-in. It keeps vendor files untouched and reloads Hyprland and logind without rebooting. Existing stay-awake settings are preserved.

Running it again replaces its own marked binding instead of adding another. If another custom lid-close binding exists, it stops before changing live settings; reconcile that binding first. Do not install overlapping lid overrides.

### Files and recovery

| Installed file | Purpose |
| --- | --- |
| `~/.config/omarchy/shell.json` | Set `idle.screensaver` and `idle.lock` to `0` |
| `~/.config/hypr/bindings.lua` | Route lid close through the AC-aware helper |
| `~/.local/bin/bash-scripts-omarchy-lid-close` | Skip locking only when logind confirms AC power |
| `/etc/systemd/logind.conf.d/90-omarchy-remote-development.conf` | Set only `HandleLidSwitchExternalPower=ignore` |

The installer prints a private backup directory under `~/.local/state/bash-scripts/omarchy/`. It stores the previous files there, never in this repository. Every run creates its own backup; keep the first one to recover the original settings. A backup of an installed helper or drop-in exists only if that file existed before that run. Files ending in `.new` are prepared replacements, not originals.

To undo, use the backup from the run you want to reverse. Review later edits before restoring complete files. Usually the narrow recovery is:

1. Restore just `idle.screensaver` and `idle.lock` from the backed-up `shell.json`.
2. Remove the `BEGIN/END bash-scripts Omarchy AC lid override` block from `bindings.lua`.
3. Restore the previous helper and drop-in if they were backed up. Otherwise remove only the two installed files listed above.
4. Run `hyprctl reload` and `sudo systemctl reload systemd-logind`.

An existing locked session stays locked until you unlock it. For a new setup, check the lid behavior while physically present before relying on unattended access. Other logind overrides or desktop power settings can affect the result.

## VM host prerequisites

[`install-vm-host-dependencies.sh`](install-vm-host-dependencies.sh) prepares the packages for a headless KVM/libvirt host on Arch/Omarchy x86_64:

```bash
# Read-only check. Exit 2 means packages are missing.
bash omarchy/install-vm-host-dependencies.sh

# Install missing packages, with the normal pacman confirmation.
bash omarchy/install-vm-host-dependencies.sh --install
```

Add `--yes` only for an already reviewed unattended transaction. The package set is `qemu-base`, `libvirt`, `dnsmasq`, `edk2-ovmf`, `cloud-image-utils`, `nftables`, `curl`, `gnupg`, `python`, and `jq`. Pacman also installs their dependencies. Run as your normal user with `sudo`, or as root through an approved provisioning path.

The installer uses existing package indexes. It never runs `pacman -Sy` or a general OS upgrade. It stops if the cached indexes show pending upgrades or the transaction cannot resolve. Keep the system current through Omarchy's normal update process before installing; stale indexes can refer to packages that mirrors no longer carry. On a mirror or dependency error, stop and resolve the system update separately rather than attempting a partial upgrade.

No VM, network, user/group membership, firewall policy or libvirt service is configured by this script. Package hooks can still run. Set up the intended network protection and guarded VM startup separately before activating libvirt or guests. The [Ubuntu guest installer](../ubuntu/README.md) covers packages inside a dedicated guest.

Reruns skip installation when all prerequisites are present. Inspect `/var/log/pacman.log` to identify the original package transaction for recovery. Retain packages used by other workloads; do not blanket-remove dependencies. Disabling a later VM is separate from removing these packages.

## GitHub access on a replacement machine

Generate a new SSH key on each machine; do not copy a private key into this repository:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github_omarchy -C "omarchy-github"
```

Add **only the `.pub` file** to your GitHub account's [SSH keys](https://github.com/settings/keys). Set the matching identity in your private `~/.ssh/config`, preserving any existing GitHub configuration:

```sshconfig
Host github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github_omarchy
    IdentitiesOnly yes
```

Use your normal passphrase/SSH-agent policy. On the first connection, compare the server fingerprint with [GitHub's published fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints), then check access with `ssh -T git@github.com`. GitHub SSH access is separate from `gh` or Codex authentication.

## Keeping this folder useful

Add a small script and document its purpose, requirements, changed files, and recovery steps whenever a new preference is adopted. Work directly on `main`; no worktrees or pull requests are needed.

Keep this public folder limited to scripts and documentation. Do not add tests, proof reports, logs, personal configuration dumps, private host addresses, credentials, keys, or backups. If a future script needs a secret, obtain it at runtime from a private local source or prompt; never put it in arguments, printed output, or a committed example. Ignore rules are a convenience, not a substitute for reviewing the diff before publishing.
