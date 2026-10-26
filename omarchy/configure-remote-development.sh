#!/usr/bin/env bash
set -euo pipefail

# Run as the desktop user from an active Omarchy terminal, without sudo.
# Only the systemd-logind drop-in needs administrator privileges.
if [[ $(uname -s) != Linux || $EUID -eq 0 || -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  echo 'Run this as your normal user inside an active Omarchy desktop.' >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_dir="$HOME/.config"
state_dir="$HOME/.local/state/bash-scripts/omarchy"
helper_file="$HOME/.local/bin/bash-scripts-omarchy-lid-close"
logind_file=/etc/systemd/logind.conf.d/90-omarchy-remote-development.conf

for command_name in python3 luac hyprctl omarchy-shell busctl systemctl sudo; do
  command -v "$command_name" >/dev/null || { echo "Missing command: $command_name" >&2; exit 1; }
done
for required_file in "$config_dir/hypr/hyprland.lua" "$config_dir/hypr/bindings.lua" \
  "$config_dir/omarchy/shell.json" /usr/bin/omarchy-system-lid-close \
  /usr/bin/omarchy-hyprland-monitor-clamshell; do
  [[ -f $required_file ]] || { echo "Required Omarchy 4 file missing: $required_file" >&2; exit 1; }
done
[[ -z $(hyprctl configerrors) ]] || { echo 'Fix existing Hyprland configuration errors first.' >&2; exit 1; }
[[ $(systemctl show systemd-logind -p CanReload --value) == yes ]] || {
  echo 'This script needs a reloadable systemd-logind service.' >&2; exit 1;
}
bash -n "$script_dir/lid-close.sh"

# All backups are private and outside the Git checkout.
umask 077
mkdir -p "$state_dir"
chmod 700 "$state_dir"
backup_dir=$(mktemp -d "$state_dir/remote-development.XXXXXXXX")
echo "Private backup: $backup_dir"

# Prepare both edited files before changing the live configuration.
python3 - "$config_dir" "$backup_dir" "$helper_file" <<'PY'
import json
import pathlib
import re
import shutil
import sys

config, backup, helper = map(pathlib.Path, sys.argv[1:])
shell = config / 'omarchy/shell.json'
bindings = config / 'hypr/bindings.lua'
for source in (shell, bindings, helper):
    if source.is_symlink():
        raise SystemExit(f'Review the symlink before running this script: {source}')
    if source.exists():
        shutil.copy2(source, backup / source.name)

settings = json.loads(shell.read_text())
idle = settings.setdefault('idle', {})
if not isinstance(idle, dict):
    raise SystemExit('Expected the Omarchy idle configuration to be a JSON object.')
idle.update(screensaver=0, lock=0)
(backup / 'shell.json.new').write_text(json.dumps(settings, indent=2) + '\n')

begin = '-- BEGIN bash-scripts Omarchy AC lid override'
end = '-- END bash-scripts Omarchy AC lid override'
original = bindings.read_text()
if original.count(begin) != original.count(end) or original.count(begin) > 1:
    raise SystemExit('Review the existing AC lid override markers before continuing.')
base = re.sub(re.escape(begin) + r'.*?' + re.escape(end) + r'\n?', '', original, flags=re.S)
if 'switch:on:Lid Switch' in base:
    raise SystemExit('A custom lid-close binding already exists. Reconcile it before running this script.')
block = '\n'.join([
    begin,
    'hl.unbind("switch:on:Lid Switch")',
    'o.bind("switch:on:Lid Switch", "Lid close (stay unlocked on AC)",',
    '  ' + json.dumps(str(helper), ensure_ascii=False) + ', { locked = true })',
    end,
    '',
])
(backup / 'bindings.lua.new').write_text(base.rstrip('\n') + '\n\n' + block)
PY

luac -p "$backup_dir/bindings.lua.new"
sudo -v
if sudo test -L "$logind_file"; then
  echo 'Review the existing logind drop-in symlink before continuing.' >&2
  exit 1
fi
if sudo test -e "$logind_file"; then
  sudo cat "$logind_file" | tee "$backup_dir/logind.conf" >/dev/null
fi
printf '[Login]\nHandleLidSwitchExternalPower=ignore\n' > "$backup_dir/logind.conf.new"

if ! cmp -s "$config_dir/omarchy/shell.json" "$backup_dir/shell.json" || \
  ! cmp -s "$config_dir/hypr/bindings.lua" "$backup_dir/bindings.lua"; then
  echo 'Configuration changed during setup. Review it and run again.' >&2
  exit 1
fi

install -Dm755 "$script_dir/lid-close.sh" "$helper_file"
install -m600 "$backup_dir/shell.json.new" "$config_dir/omarchy/shell.json"
install -m600 "$backup_dir/bindings.lua.new" "$config_dir/hypr/bindings.lua"
sudo install -Dm644 "$backup_dir/logind.conf.new" "$logind_file"
sudo systemctl reload systemd-logind
hyprctl reload

lid_policy=$(busctl get-property org.freedesktop.login1 \
  /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitchExternalPower)
if [[ $lid_policy != 's "ignore"' ]]; then
  echo 'The AC lid policy is overridden elsewhere. Review the logind drop-ins.' >&2
  exit 1
fi
config_errors=$(hyprctl configerrors)
if [[ -n $config_errors ]]; then
  printf 'Hyprland reported configuration errors:\n%s\nUse the README recovery instructions.\n' "$config_errors" >&2
  exit 1
fi
echo 'Configured: no idle lock/screensaver; no lid-close suspend or lock on AC.'
echo 'An already locked session still needs to be unlocked once.'
echo "Keep the private backup if you want to restore the previous settings: $backup_dir"
