# Ubuntu runner guest prerequisites

[`install-runner-guest-dependencies.sh`](install-runner-guest-dependencies.sh) installs the OS dependencies for two systemd/Podman CI runner slots inside a dedicated **Ubuntu 24.04 amd64 VM**. It checks that systemd is running in a VM and rejects physical hosts and containers.

From this repository's root inside the guest:

```bash
# Read-only check. Exit 2 means packages are missing.
bash ubuntu/install-runner-guest-dependencies.sh

# Install the missing dependencies, with the normal apt confirmation.
bash ubuntu/install-runner-guest-dependencies.sh --install
```

For an already reviewed unattended installation, add `--yes`. Run as the normal user with `sudo` available, or as root through the VM's approved provisioning path. Enter passwords only at the native prompt.

The package set is `podman`, `qemu-guest-agent`, `catatonit`, `jq`, `curl`, `nftables`, and `python3-cryptography`. Install mode updates apt indexes and installs missing packages with `--no-install-recommends --no-remove`. It does not run a distribution upgrade, add repositories or remove packages. Required dependencies can be upgraded by apt. Package maintainer scripts may start or enable services; review apt's transaction on an existing guest.

Running the script again checks installed package state. It does not refresh indexes or invoke privileged commands when every prerequisite is already configured. This check is package presence, not runtime acceptance or a security update policy.

VM/domain definitions, SSH access, guest-agent and fstrim enablement, network isolation, runner images, units, and enrollment credentials belong to the deployment setup. This installer does not configure them. Job PHP, Node, Composer and browser dependencies belong inside the disposable runner image, not the guest OS. Keep private deployment inputs outside this public repository.

## Recovery

Review `/var/log/apt/history.log` for the exact transaction. Do not run blanket removal or autoremove on a shared machine. For a newly provisioned disposable guest, rebuilding from the verified base image is the simplest recovery. If preserving the guest, remove only packages added by the recorded transaction after confirming that no service depends on them. A failed install stops and preserves apt's diagnostic status; repair the package-manager state before rerunning.
