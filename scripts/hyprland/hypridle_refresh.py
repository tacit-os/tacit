#!/usr/bin/env python3
# The person's hypridle.conf, when Settings made it, brought up to Tacit's at login, with their times kept (and a
# listener they turned off with Never kept off). Settings > Lock & sleep changes a time by copying the packaged file
# into ~/.config/hypr, which hypridle reads first, so a later fix to the packaged file (the lock command, the Wi-Fi step
# after sleep) never reached anyone who had changed a time. A copy Settings makes says so on its first line (MARK,
# tacit-settings.qml's idleMark); one made before it did is known by being a packaged file but for its times. Any other
# file is the person's own and is left as it is.
#   hypridle_refresh.py [packaged] [theirs]   by default the hypridle.conf of $XDG_CONFIG_DIRS and of ~/.config/hypr
import hashlib
import os
import re
import sys
import tempfile

MARK = "# Made by Settings > Lock & sleep from Tacit's hypridle.conf, with your times: the rest is Tacit's again at each login. Delete this line to keep edits of your own."
# a listener Settings turned off (Never) has each of its lines behind this, which hypridle reads as a comment
OFF = "#off "

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


# each listener as [first line index, timeout line index, last line index, kind, turned off]
def listeners(lines):
    out, start, at, run, inside, off = [], -1, -1, "", False, False
    for i, raw in enumerate(lines):
        line = raw.removeprefix(OFF)
        if re.match(r"\s*listener\s*\{", line):
            start, at, run, inside, off = i, -1, "", True, raw.startswith(OFF)
        elif inside and re.match(r"\s*timeout\s*=", line):
            at = i
        elif inside and re.match(r"\s*on-timeout\s*=", line):
            run = line.split("=", 1)[1]
        elif inside and re.match(r"\s*\}", line):
            inside = False
            if at >= 0 and kind(run):
                out.append((start, at, i, kind(run), off))
    return out


def refreshed(packaged, theirs):
    old = theirs.split("\n")
    times = {}
    for _, at, _, k, off in listeners(old):
        m = re.match(r"\s*timeout\s*=\s*(\d+)", old[at].removeprefix(OFF))
        if m and k not in times:
            times[k] = (m.group(1), off)
    lines = packaged.split("\n")
    for start, at, end, k, _ in listeners(lines):
        m = re.match(r"(\s*)timeout\s*=\s*(\d+)", lines[at])
        if k in times and m and m.group(2) != times[k][0]:
            lines[at] = f"{m.group(1)}timeout = {times[k][0]}"
        # turned off by Never: off again in Tacit's file
        if k in times and times[k][1]:
            lines[start:end + 1] = [OFF + line for line in lines[start:end + 1]]
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
