# Laptop fan commands

[`fans.py`](fans.py) provides the same commands on two verified laptop models:

```bash
fans max     # Maximum cooling
fans auto    # Return fan control to firmware
fans status  # Show the current mode and speed
```

`auto` removes the manual override. It does not stop the fan. Firmware chooses
the speed from temperatures and its normal thermal policy. These commands do
not change CPU power profiles, install a daemon or add boot persistence.

## Acer Predator PH315-53, BIOS V2.04

The dispatcher calls the existing root-owned
[`predator-ph315-53-fans`](../omarchy/README.md#predator-ph315-53-fan-cooling)
helper. That helper must already be installed with the source hash this
dispatcher verifies. Both CPU and GPU fans are controlled. Run as the normal
user; sudo prompts for the usual password when necessary.

Install the shortcut in the user-local command directory, if that path is
unused and the directory is already in your shell's PATH:

```bash
install -d -m 0755 ~/.local/bin
install -m 0755 hardware/fans.py ~/.local/bin/fans
```

The displayed Acer speed values are raw firmware readings, not calibrated RPM.
The original helper remains available independently of this shortcut.

## Dell Inspiron 15 5510, BIOS 2.37.0

The dispatcher discovers the existing `dell_smm` hwmon device by name, checks
single-fan coverage and uses the kernel's documented control: mode 1 selects
manual maximum and mode 2 restores automatic BIOS control. It verifies readback
and attempts to restore the prior setting if a change fails. It stops on
unknown topology or a competing fan-control daemon. Thermald remains enabled.

Install the reviewed command in an unused root-owned path:

```bash
sudo install -m 0755 hardware/fans.py /usr/local/bin/fans
```

Root sessions can use the commands directly. Other users need `sudo fans max`
or `sudo fans auto`; `fans status` is read-only. No sudo policy is installed.
Maximum is the firmware's highest fan setting; measured RPM can differ from
its nominal target. See the [kernel driver documentation](https://docs.kernel.org/hwmon/dell-smm-hwmon.html).

## Recovery and removal

Use `fans auto` to hand control back to firmware. Firmware, suspend, reboot or
another fan controller may change the selected mode; these commands add no
startup override. Unsupported firmware needs a fresh compatibility check.

Removing the shortcut does not change the selected fan mode. Return to `auto`
first if that is the desired state, then remove only the installed `fans` file.
Keep the existing Acer helper. Do not replace unrelated commands at these paths.
