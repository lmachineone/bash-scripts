#!/usr/bin/env bash
set -euo pipefail

# Keep the session unlocked only when logind confirms external power.
# Battery power or an unreadable power state uses Omarchy's normal handler.
power_state=$(/usr/bin/busctl get-property org.freedesktop.login1 \
  /org/freedesktop/login1 org.freedesktop.login1.Manager OnExternalPower 2>/dev/null) || power_state=unknown

if [[ $power_state == 'b true' ]]; then
  exec /usr/bin/omarchy-hyprland-monitor-clamshell
fi

exec /usr/bin/omarchy-system-lid-close
