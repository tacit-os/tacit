#!/usr/bin/env python3
"""Default apps for the Settings app.

  default_apps.py list              JSON: {role: {"current": id, "options": [{"id", "name", "exec"}]}}
  default_apps.py set ROLE ID       make ID (a .desktop id) the default for ROLE

A role is a set of MIME types, written with `xdg-mime default`. The browser, the file manager and
the terminal are also what Super+W, Super+E and Super+Return open, and those keys read Lua variables
(hyprland/variables.lua), not mimeapps.list - so `set` also writes those three into a marked block
of ~/.config/hypr/custom/variables.lua and reloads Hyprland. The terminal role has no MIME type: it
is chosen from apps in the TerminalEmulator category, and its current value is the shell's
apps.terminal, which the Settings app writes itself.
"""
import json
import os
import re
import shutil
import subprocess
import sys

# "also": the other types Tacit gives that role's app (session/xdg/mimeapps.list), written with the role's own so that
# the choice holds for them too (a phone's .mov stayed in Viewer after choosing a video player); only "mimes" picks the
# apps offered.
ROLES = {
    "browser": {"mimes": ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"], "var": "browser"},
    "files": {"mimes": ["inode/directory"], "var": "fileManager"},
    "terminal": {"category": "TerminalEmulator", "var": "terminal"},
    "mail": {"mimes": ["x-scheme-handler/mailto"]},
    "images": {"mimes": ["image/png", "image/jpeg", "image/webp", "image/gif"],
               "also": ["image/bmp", "image/tiff", "image/svg+xml", "image/x-icon"]},
    "video": {"mimes": ["video/mp4", "video/x-matroska", "video/webm"], "also": ["video/quicktime", "video/x-msvideo", "video/x-m4v"]},
    "music": {"mimes": ["audio/mpeg", "audio/flac", "audio/ogg"],
              "also": ["audio/x-flac", "audio/x-wav", "audio/wav", "audio/mp4", "audio/x-m4a", "audio/aac", "audio/opus"]},
    "pdf": {"mimes": ["application/pdf"]},
    "text": {"mimes": ["text/plain"], "also": ["text/markdown", "application/json", "text/x-python", "text/x-shellscript",
                                               "text/x-qml", "application/javascript", "text/x-csrc"]},
}

HOME = os.path.expanduser("~")
VARIABLES = os.path.join(HOME, ".config/hypr/custom/variables.lua")
BEGIN = "-- >>> Tacit Settings: default apps (written by Settings)"
END = "-- <<< Tacit Settings: default apps"
# Tacit's own Files is driven over the shell's IPC; its .desktop Exec is a quoted sh -c wrapper
# that is awkward to pass through a Lua string.
OWN_FILES = {"quiet-files.desktop": 'qs -p "${TACIT_SHELL:-$HOME/.config/quickshell/tacit}" ipc call files open'}


def app_dirs():
    data_home = os.environ.get("XDG_DATA_HOME", os.path.join(HOME, ".local/share"))
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    return [os.path.join(d, "applications") for d in [data_home, *data_dirs]]


def read_entries():
    """Visible applications by desktop id; the first directory that has an id wins."""
    entries = {}
    for d in app_dirs():
        if not os.path.isdir(d):
            continue
        for root, _, files in os.walk(d):
            for f in files:
                if not f.endswith(".desktop"):
                    continue
                did = os.path.relpath(os.path.join(root, f), d).replace("/", "-")
                if did in entries:
                    continue
                e = parse(os.path.join(root, f))
                if e is not None:
                    entries[did] = e
    # NoDisplay apps stay: they are kept out of menus, not out of opening files (imv is one)
    return {k: v for k, v in entries.items() if v.get("Type") == "Application" and v.get("Hidden") != "true"}


def parse(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            section, out = None, {}
            for line in fh:
                line = line.strip()
                if line.startswith("["):
                    section = line
                    continue
                if section == "[Desktop Entry]" and "=" in line:
                    k, v = line.split("=", 1)
                    out.setdefault(k.strip(), v.strip())
            return out
    except OSError:
        return None


def plain_exec(e):
    return re.sub(r"\s*%[fFuUdDnNickvm]", "", e.get("Exec", "")).strip()


def current_default(mime):
    try:
        return subprocess.run(["xdg-mime", "query", "default", mime], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def options_for(role, entries, current=""):
    spec = ROLES[role]
    out = []
    for did, e in entries.items():
        if "category" in spec:
            ok = spec["category"] in e.get("Categories", "").split(";") and e.get("NoDisplay") != "true"
        else:
            mimes = e.get("MimeType", "").split(";")
            ok = any(m in mimes for m in spec["mimes"])
        # the app in use is always offered, even when it declares no type itself (zathura's
        # formats are declared by its plugins)
        if ok or did == current:
            out.append({"id": did, "name": e.get("Name", did).strip(), "exec": plain_exec(e)})
    # One row per name: an app often ships a hidden twin (a URL handler, a plugin). The one in
    # use wins, then the one shown in menus.
    best = {}
    for o in out:
        key = o["name"].lower()
        rank = (o["id"] == current, entries[o["id"]].get("NoDisplay") != "true")
        if key not in best or rank > best[key][0]:
            best[key] = (rank, o)
    return sorted((o for _, o in best.values()), key=lambda o: o["name"].lower())


def launcher(did, e):
    if did in OWN_FILES:
        return OWN_FILES[did]
    if shutil.which("gtk-launch"):
        return f"gtk-launch {did[:-len('.desktop')]}"
    return plain_exec(e)


def write_variable(name, value):
    """Sets one variable inside the marked block, keeping everything else in the file."""
    try:
        with open(VARIABLES, encoding="utf-8") as fh:
            text = fh.read()
    except FileNotFoundError:
        text = ""
    block = {}
    if BEGIN in text and END in text:
        head, rest = text.split(BEGIN, 1)
        body, tail = rest.split(END, 1)
        for line in body.strip().splitlines():
            m = re.match(r"(\w+) = \[\[(.*)\]\]$", line.strip())
            if m:
                block[m.group(1)] = m.group(2)
    else:
        head, tail = text, ""
        if head and not head.endswith("\n"):
            head += "\n"
    block[name] = value
    lines = [f"{k} = [[{v}]]" for k, v in block.items()]
    new = head + BEGIN + "\n" + "\n".join(lines) + "\n" + END + tail
    os.makedirs(os.path.dirname(VARIABLES), exist_ok=True)
    tmp = VARIABLES + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(new if new.endswith("\n") else new + "\n")
    os.replace(tmp, VARIABLES)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "list":
        entries = read_entries()
        out = {}
        for role, spec in ROLES.items():
            current = current_default(spec["mimes"][0]) if "mimes" in spec else ""
            out[role] = {"current": current, "options": options_for(role, entries, current)}
        print(json.dumps(out))
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "set" and sys.argv[2] in ROLES:
        role, did = sys.argv[2], sys.argv[3]
        entries = read_entries()
        if did not in entries:
            print(f"unknown app {did}", file=sys.stderr)
            return 1
        spec = ROLES[role]
        if "mimes" in spec:
            subprocess.run(["xdg-mime", "default", did, *spec["mimes"], *spec.get("also", [])], check=False)
        if "var" in spec:
            # the terminal is given its plain command: the shell runs `<terminal> -e ...` with it
            value = plain_exec(entries[did]) if role == "terminal" else launcher(did, entries[did])
            write_variable(spec["var"], value)
            subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
