#!/usr/bin/env python3
# Whether pam_faillock has locked an account, decided as its preauth check decides it, and the settings that say for
# how long. While the account is locked the right password fails too, so the lock, the boot lock and an app's password
# request say so (services/Faillock.qml) instead of "Incorrect password".
#   faillock.py [user] [faillock.conf] [system-auth]   by default this account, /etc/security/faillock.conf and
#                                                       /etc/pam.d/system-auth
# Prints {"locked": bool, "deny": n, "minutes": n}: minutes is the lock's length, 0 for one that lasts until it is reset.
import getpass
import json
import math
import struct
import sys
import time

DEFAULTS = {"dir": "/run/faillock", "deny": 3, "fail_interval": 900, "unlock_time": 600}
RECORD = struct.Struct("=52sHHQ")   # faillock.h's struct tally: source, reserved, status, time
VALID = 0x1


def text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def settings(conf, pam):
    s = dict(DEFAULTS)

    def take(key, value):
        if key == "dir" and value:
            s["dir"] = value
        elif key == "unlock_time" and value == "never":
            s[key] = 0
        elif key in ("deny", "fail_interval", "unlock_time") and value.isdigit():
            s[key] = int(value)

    for line in text(conf).splitlines():
        key, eq, value = line.split("#", 1)[0].partition("=")
        if eq:
            take(key.strip(), value.strip())
    # the arguments on the auth stack's preauth line, which pam_faillock reads after the file
    for line in text(pam).splitlines():
        words = line.split("#", 1)[0].split()
        if "pam_faillock.so" in words and "preauth" in words:
            for word in words[words.index("pam_faillock.so") + 1:]:
                key, eq, value = word.partition("=")
                if eq:
                    take(key, value)
    return s


def locked(user, s, now):
    try:
        with open(f"{s['dir']}/{user}", "rb") as f:
            data = f.read()
    except OSError:
        return False    # no failures recorded, or none this account may read
    data = data[:len(data) - len(data) % RECORD.size]
    times = [t for _, _, status, t in RECORD.iter_unpack(data) if status & VALID]
    if not s["deny"] or not times:
        return False
    latest = max(times)
    failures = sum(1 for t in times if latest - t < s["fail_interval"])
    return failures >= s["deny"] and (s["unlock_time"] == 0 or latest + s["unlock_time"] >= now)


if __name__ == "__main__":
    user = sys.argv[1] if len(sys.argv) > 1 else getpass.getuser()
    s = settings(sys.argv[2] if len(sys.argv) > 2 else "/etc/security/faillock.conf",
                 sys.argv[3] if len(sys.argv) > 3 else "/etc/pam.d/system-auth")
    print(json.dumps({"locked": locked(user, s, time.time()), "deny": s["deny"], "minutes": math.ceil(s["unlock_time"] / 60)}))
