#!/usr/bin/env python3
# The person's hypridle.conf, when Settings made it, brought up to Tacit's at login, with their times kept. Settings >
# Lock & sleep changes a time by copying the packaged file into ~/.config/hypr, which hypridle reads first, so a later fix
# to the packaged file (the lock command, the Wi-Fi step after sleep) never reached anyone who had changed a time. A copy
# Settings makes says so on its first line (MARK, tacit-settings.qml's idleMark); one made before it did is known by
# being a packaged file but for its times. Any other file is the person's own and is left as it is.
#   hypridle_refresh.py [packaged] [theirs]   by default the hypridle.conf of $XDG_CONFIG_DIRS and of ~/.config/hypr
import hashlib
import os
import re
import sys
import tempfile

MARK = "# Made by Settings > Lock & sleep from Tacit's hypridle.conf, with your times: the rest is Tacit's again at each login. Delete this line to keep edits of your own."

# session/xdg/hypr/hypridle.conf as Tacit shipped it before Settings marked its copies (322d244, 37b4ded, f169121), each
# with its timeout lines blanked (masked)
SHIPPED = {
    "30b659f16bb3716e9aefdb4d9606e727d1dddd0eb890968f86257ca6f2dfc6f8",
    "f35b7ec06824f04286cafb398e91bffa721fb1febe8622a8f09457ee729bef2d",
    "d9bc0eed3b5098ec865db939f1bdde2f39d4adeaec67db7f215bb4af4150254c",
}


def masked(text):
    return re.sub(r"(?m)^([ \t]*)timeout[ \t]*=.*$", r"\1timeout =", text)


# what a listener is for, told by what its on-timeout runs (Settings' idleKind)
def kind(run):
    return "sleep" if re.search(r"suspend|hibernate", run) else "screen" if "dpms" in run else "lock" if "lock" in run else ""


# each listener as [timeout line index, kind]
def listeners(lines):
    out, at, run, inside = [], -1, "", False
    for i, line in enumerate(lines):
        if re.match(r"\s*listener\s*\{", line):
            at, run, inside = -1, "", True
        elif inside and re.match(r"\s*timeout\s*=", line):
            at = i
        elif inside and re.match(r"\s*on-timeout\s*=", line):
            run = line.split("=", 1)[1]
        elif inside and re.match(r"\s*\}", line):
            inside = False
            if at >= 0 and kind(run):
                out.append((at, kind(run)))
    return out


def refreshed(packaged, theirs):
    old = theirs.split("\n")
    times = {}
    for at, k in listeners(old):
        m = re.match(r"\s*timeout\s*=\s*(\d+)", old[at])
        if m and k not in times:
            times[k] = m.group(1)
    lines = packaged.split("\n")
    for at, k in listeners(lines):
        m = re.match(r"(\s*)timeout\s*=\s*(\d+)", lines[at])
        if k in times and m and m.group(2) != times[k]:
            lines[at] = f"{m.group(1)}timeout = {times[k]}"
    return MARK + "\n" + "\n".join(lines)


def main():
    dirs = os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg"
    packaged = sys.argv[1] if len(sys.argv) > 1 else next(
        (p for p in (os.path.join(d, "hypr", "hypridle.conf") for d in dirs.split(":") if d) if os.path.isfile(p)), "")
    home = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(home, "hypr", "hypridle.conf")
    try:
        with open(packaged) as f:
            new = f.read()
        with open(path) as f:
            text = f.read()
    except OSError:
        return
    first, _, rest = text.partition("\n")
    if first == MARK:
        out = refreshed(new, rest)
    elif hashlib.sha256(masked(text).encode()).hexdigest() in SHIPPED:
        out = refreshed(new, text)
    else:
        return
    if out == text:
        return
    with tempfile.NamedTemporaryFile("w", dir=os.path.dirname(path), delete=False) as f:
        f.write(out)
    os.chmod(f.name, os.stat(path).st_mode)
    os.replace(f.name, path)
    print(f"hypridle.conf brought up to {packaged}, times kept")


if __name__ == "__main__":
    main()
