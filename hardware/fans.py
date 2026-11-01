#!/usr/bin/env python3
"""Select maximum cooling or firmware automatic control on verified laptops."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import time

ACER_HELPER = Path('/usr/local/bin/predator-ph315-53-fans')
ACER_SHA256 = '05826389c65677e706f56d0455bc0e7664961e8e670fdaa91d8de71026dc743b'
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
        label = {automatic: 'Automatic (firmware)', maximum: 'Maximum'}.get(value)
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
    result = {name: int((device / name).read_text().strip())
              for name in ['pwm1_enable', 'pwm1', 'fan1_input']}
    if result['pwm1_enable'] not in (1, 2) or not 0 <= result['pwm1'] <= 255:
        raise RuntimeError('Unrecognized native fan-control state')
    return result


def dell_set(device, mode):
    before = dell_snapshot(device)
    desired = 1 if mode == 'max' else 2
    try:
        # The kernel maps 1 to manual maximum and 2 to automatic BIOS control.
        (device / 'pwm1_enable').write_text(f'{desired}\n')
        time.sleep(2)
        after = dell_snapshot(device)
        if after['pwm1_enable'] != desired or (mode == 'max' and after['pwm1'] != 255):
            raise RuntimeError('Fan-mode readback mismatch')
        return after
    except BaseException:
        try:
            (device / 'pwm1_enable').write_text(f"{before['pwm1_enable']}\n")
            if before['pwm1_enable'] == 1:
                (device / 'pwm1').write_text(f"{before['pwm1']}\n")
            restored = dell_snapshot(device)
            if restored['pwm1_enable'] != before['pwm1_enable'] or (
                before['pwm1_enable'] == 1 and restored['pwm1'] != before['pwm1']
            ):
                raise RuntimeError('Original fan state did not return')
        except BaseException as error:
            raise RuntimeError('Fan change failed and recovery could not be verified; inspect native control') from error
        raise


def dell(mode):
    if mode != 'status' and os.geteuid() != 0:
        raise RuntimeError(f'Run sudo fans {mode}')
    device = dell_path()
    if mode == 'status':
        data = dell_snapshot(device)
    else:
        for process in Path('/proc').glob('[0-9]*/comm'):
            try:
                if process.read_text().strip() in {'fancontrol', 'i8kmon', 'nbfc_service'}:
                    raise RuntimeError('Another fan controller is active')
            except (FileNotFoundError, ProcessLookupError):
                pass
        descriptor = os.open('/run/lock/laptop-fans.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, 'r+') as lock:
            info = os.fstat(lock.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
                raise RuntimeError('Fan lock must be a root-owned, protected regular file')
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            data = dell_set(device, mode)
    label = 'Automatic (firmware)' if data['pwm1_enable'] == 2 else (
        'Maximum' if data['pwm1'] == 255 else f"Manual PWM {data['pwm1']}/255"
    )
    print(f"Dell fan: {label}; {data['fan1_input']} RPM")


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
