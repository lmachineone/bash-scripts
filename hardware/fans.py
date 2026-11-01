#!/usr/bin/env python3
"""Select maximum cooling or firmware automatic control on verified laptops."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess

ACER_HELPER = Path('/usr/local/bin/predator-ph315-53-fans')
ACER_SHA256 = '478a5009c16a017cdb6722b7b8ed38cc080cff11404a43801e195f6bebd39908'
DMI = Path('/sys/class/dmi/id')


def acer(mode):
    info = ACER_HELPER.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
        raise RuntimeError('Acer helper must be a root-owned, protected regular file')
    if hashlib.sha256(ACER_HELPER.read_bytes()).hexdigest() != ACER_SHA256:
        raise RuntimeError('Acer helper changed; verify its source before updating this dispatcher')
    command = [str(ACER_HELPER), mode]
    if os.geteuid() != 0:
        command.insert(0, '/usr/bin/sudo')
    result = subprocess.run(command, stdout=subprocess.PIPE, text=True, check=True)
    data = json.loads(result.stdout)
    modes = data['after']['modes']
    for name, register, automatic, maximum in [('cpu', '34', 0x54, 0x58), ('gpu', '33', 0x50, 0x60)]:
        value = modes[register]
        label = {0: 'Automatic (firmware)', automatic: 'Automatic (firmware)', maximum: 'Maximum'}.get(value)
        if label is None:
            raise RuntimeError('Unexpected Acer helper result')
        print(f"Acer {name.upper()} fan: {label}; raw speed {data['after']['fan_speed_raw'][name]}")
    print(f"Power profile: {data['power_profile']} (unchanged). Speed values are firmware scalars, not calibrated RPM.")


def dell_path():
    matches = [p for p in Path('/sys/class/hwmon').glob('hwmon*')
               if (p / 'name').read_text().strip() == 'dell_smm']
    if len(matches) != 1:
        raise RuntimeError('Expected exactly one native dell_smm device')
    device = matches[0]
    if sorted(p.name for p in device.glob('fan*_input')) != ['fan1_input']:
        raise RuntimeError('Fan topology differs from the verified single-fan model')
    if sorted(p.name for p in device.glob('pwm*')) != ['pwm1', 'pwm1_enable']:
        raise RuntimeError('Expected the native single-fan automatic-control interface')
    return device


def dell_snapshot(device):
    mode = int((device / 'pwm1_enable').read_text().strip())
    # The driver returns ENODATA for PWM while the special automatic state is active.
    result = {'pwm1_enable': mode, 'pwm1': None if mode == 2 else int((device / 'pwm1').read_text().strip()),
              'fan1_input': int((device / 'fan1_input').read_text().strip())}
    if mode not in (1, 2) or (mode == 1 and not 0 <= result['pwm1'] <= 255):
        raise RuntimeError('Unrecognized native fan-control state')
    return result


def dell(mode):
    if mode != 'status':
        raise RuntimeError('Dell fan override unavailable: this firmware rejected automatic-control recovery; no setting changed')
    data = dell_snapshot(dell_path())
    print(f"Dell fan: {data['fan1_input']} RPM; reported PWM {data['pwm1']}/255")
    print('Maximum/automatic switching is unavailable on this verified firmware. PWM alone does not prove control ownership.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', nargs='?', default='status', choices=['status', 'max', 'auto'],
                        help='max: maximum cooling; auto: firmware control; status: current mode')
    args = parser.parse_args()
    identity = tuple((DMI / name).read_text().strip() for name in ['sys_vendor', 'product_name', 'bios_version'])
    if identity == ('Acer', 'Predator PH315-53', 'V2.04'):
        acer(args.mode)
    elif identity == ('Dell Inc.', 'Inspiron 15 5510', '2.37.0'):
        dell(args.mode)
    else:
        raise RuntimeError('Unsupported hardware/firmware; no fan setting changed')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
