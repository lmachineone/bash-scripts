#!/usr/bin/env python3
"""Select firmware Auto/Maximum fans on the verified PH315-53/V2.04 cohort.

Fan register meanings: PredatorNonSense main.py at commit
75fd228ca43bc85f6f25770ee8e0670e29d58df1 (MIT, Phani Pavan Kambhampati).
https://github.com/kphanipavan/PredatorNonSense
This implementation does not use its GUI or other hardware controls.
"""

import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time

MODES = {"auto": {0x22: 0x54, 0x21: 0x50}, "max": {0x22: 0x58, 0x21: 0x60}}
EC_FILE = "/sys/kernel/debug/ec/ec0/io"


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed with exit {result.returncode}")
    return result.stdout.strip()


def read_byte(fd, register):
    value = os.pread(fd, 1, register)
    if len(value) != 1:
        raise RuntimeError("Short embedded-controller read")
    return value[0]


def snapshot(fd):
    modes = {register: read_byte(fd, register) for register in MODES["auto"]}
    for register, value in modes.items():
        if value not in (MODES["auto"][register], MODES["max"][register]):
            raise RuntimeError(f"Unverified fan mode at 0x{register:02x}: 0x{value:02x}")
    raw = {}
    for name, register in (("cpu", 0x13), ("gpu", 0x15)):
        value = os.pread(fd, 2, register)
        if len(value) != 2:
            raise RuntimeError("Short fan-speed read")
        raw[name] = int.from_bytes(value, "little")
        if not 0 <= raw[name] <= 12000:
            raise RuntimeError("Fan-speed reading outside the verified sanity range")
    return {"modes": modes, "fan_speed_raw": raw}


def write_modes(fd, desired):
    for register, value in desired.items():
        if os.pwrite(fd, bytes([value]), register) != 1:
            raise RuntimeError("Short fan-mode write")
    time.sleep(2)
    if any(read_byte(fd, register) != value for register, value in desired.items()):
        raise RuntimeError("Fan-mode readback mismatch")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("status", "max", "auto"))
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise RuntimeError("Run with sudo")
    if Path("/sys/class/dmi/id/product_name").read_text().strip() != "Predator PH315-53":
        raise RuntimeError("Only Predator PH315-53 is supported")
    if Path("/sys/class/dmi/id/bios_version").read_text().strip() != "V2.04":
        raise RuntimeError("Only the verified V2.04 firmware is supported")
    for process in Path("/proc").glob("[0-9]*/comm"):
        try:
            if process.read_text().strip() in {"nbfc_service", "asensed", "fancontrol"}:
                raise RuntimeError("Another fan controller is active")
        except (FileNotFoundError, ProcessLookupError):
            pass
    with open("/run/lock/predator-ph315-53-fans.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        owned_module = not Path("/sys/module/ec_sys").exists()
        writing = args.mode != "status"
        before_profile = command("powerprofilesctl", "get")
        try:
            if owned_module:
                command("modprobe", "ec_sys", f"write_support={int(writing)}")
            if writing and Path("/sys/module/ec_sys/parameters/write_support").read_text().strip() != "Y":
                raise RuntimeError("Existing ec_sys module is read-only; preserve its owner")
            fd = os.open(EC_FILE, os.O_RDWR if writing else os.O_RDONLY)
            try:
                before = snapshot(fd)
                if writing:
                    try:
                        write_modes(fd, MODES[args.mode])
                        after = snapshot(fd)
                        if command("powerprofilesctl", "get") != before_profile:
                            raise RuntimeError("Power profile changed during fan control")
                    except BaseException:
                        write_modes(fd, before["modes"])
                        raise
                else:
                    after = before
            finally:
                os.close(fd)
        finally:
            if owned_module and Path("/sys/module/ec_sys").exists():
                command("modprobe", "-r", "ec_sys")
        print(json.dumps({"requested": args.mode, "before": before, "after": after,
                          "power_profile": before_profile, "speed_unit": "raw EC scalar; not verified RPM",
                          "ec_sys_loaded_by_this_command": owned_module,
                          "ec_sys_remaining": Path("/sys/module/ec_sys").exists()}))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error)) from error
