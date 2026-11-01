# Laptop fan commands

[`fans.py`](fans.py) provides these commands on the verified Acer Predator:

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

The helper recognizes both the normal automatic values and the zero automatic
state documented by its original controller source. This supports a fresh boot
without treating an unknown mode as safe.

Install the shortcut in the user-local command directory, if that path is
unused and the directory is already in your shell's PATH:

```bash
install -d -m 0755 ~/.local/bin
install -m 0755 hardware/fans.py ~/.local/bin/fans
```

The displayed Acer speed values are raw firmware readings, not calibrated RPM.
The original helper remains available independently of this shortcut.

## Dell Inspiron 15 5510, BIOS 2.37.0

**Status only.** Native testing on this firmware rejected the kernel's automatic
control command with `EINVAL`. The presence of `pwm1_enable` does not establish
working firmware support. Both `fans max` and `fans auto` therefore refuse without
changing any setting. Do not enable an override until automatic recovery works.

`fans status` discovers the existing `dell_smm` device by name and checks
single-fan coverage. It reports RPM and the driver's PWM reading. Maximum PWM
alone does not prove that firmware automatic control is disabled. Thermald
remains enabled. See the [kernel driver documentation](https://docs.kernel.org/hwmon/dell-smm-hwmon.html).

Install the reviewed command in an unused root-owned path:

```bash
sudo install -m 0755 hardware/fans.py /usr/local/bin/fans
```

`fans status` is read-only. No sudo policy or alternative firmware command is
installed. No reliable maximum/automatic toggle is claimed for this model.

## Recovery and removal

On Acer, use `fans auto` to hand control back to firmware. Firmware, suspend, reboot or
another fan controller may change the selected mode; these commands add no
startup override. Unsupported firmware needs a fresh compatibility check.

Removing the shortcut does not change the selected fan mode. Return to `auto`
first if that is the desired state, then remove only the installed `fans` file.
Keep the existing Acer helper. Do not replace unrelated commands at these paths.
