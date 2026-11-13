#!/usr/bin/env python3
"""phone-icon.py <app> <summary> <body> <cache dir>
   phone-icon.py --all <cache dir>              every notification the phone still holds, as a JSON list
   phone-icon.py --prune <cache dir> <keep>...  delete cached icons not named (the history no longer has them)

A phone notification (KDE Connect) reaches the notification server as pixels only. KDE Connect keeps the same
notification on D-Bus with the icon's file (/tmp/kdeconnect_$USER/<hash>), whether it is a conversation, and whether
the phone posted it silently. This finds it, copies the icon into <cache dir> (content-named, so the history keeps
it), and says what the icon is: "glyph" (the app's one-colour status icon: white on transparent) or "picture" (a
colour app icon, a contact's photo, album art). Prints one JSON object; {} when nothing matches.
"""
import json
import os
import shutil
import subprocess
import sys

BUS = ["busctl", "--user", "--json=short"]
IFACE = "org.kde.kdeconnect.device.notifications.notification"


def norm(s):
    return " ".join((s or "").split()).lower()[:80]


def props(path):
    out = subprocess.run(BUS + ["call", "org.kde.kdeconnect", path, "org.freedesktop.DBus.Properties", "GetAll", "s", IFACE],
                         capture_output=True, text=True, timeout=3).stdout
    data = json.loads(out)["data"][0] if out.strip() else {}
    return {k: v.get("data") for k, v in data.items()}


def kind(path):
    try:
        from PIL import Image
    except ImportError:
        return "picture"   # without Pillow the icon is still kept, drawn as it is
    im = Image.open(path).convert("RGBA")
    im.thumbnail((48, 48))
    raw = im.tobytes()
    total = len(raw) // 4
    seen = [tuple(raw[i:i + 3]) for i in range(0, len(raw), 4) if raw[i + 3] > 128]
    if not seen or len(seen) > 0.9 * total:
        return "picture"   # opaque: a photo, art, or a full-bleed icon
    light = sum(1 for r, g, b in seen if min(r, g, b) > 200 and max(r, g, b) - min(r, g, b) < 30)
    return "glyph" if light > 0.85 * len(seen) else "picture"


def records():
    tree = subprocess.run(["busctl", "--user", "tree", "org.kde.kdeconnect", "--list"], capture_output=True, text=True, timeout=3).stdout
    paths = [p for p in tree.split() if "/notifications/" in p and p.rsplit("/", 1)[-1].isdigit()]
    # newest first: KDE Connect numbers them as they arrive
    paths.sort(key=lambda p: int(p.rsplit("/", 1)[-1]), reverse=True)
    return paths


def described(n, cache):
    icon = n.get("iconPath") or ""
    res = {"conversation": bool(n.get("isConversation")), "silent": bool(n.get("silent")),
           "package": (n.get("internalId") or "").split("|")[1] if "|" in (n.get("internalId") or "") else ""}
    if n.get("hasIcon") and os.path.isfile(icon):
        os.makedirs(cache, exist_ok=True)
        dest = os.path.join(cache, os.path.basename(icon) + ".png")
        if not os.path.exists(dest):
            shutil.copyfile(icon, dest)
        res.update({"path": dest, "kind": kind(dest)})
    return res


def main():
    if sys.argv[1] == "--prune":
        cache, keep = sys.argv[2], set(os.path.basename(k) for k in sys.argv[3:])
        for f in os.listdir(cache) if os.path.isdir(cache) else []:
            if f.endswith(".png") and f not in keep:
                os.remove(os.path.join(cache, f))
        print("{}")
        return
    if sys.argv[1] == "--all":
        out = []
        for p in records():
            # one record that cannot be read (an icon file cut short, an answer that times out) is left out, not the list
            try:
                n = props(p)
                out.append(dict(described(n, sys.argv[2]), app=n.get("appName") or "", title=n.get("title") or "", text=n.get("text") or ""))
            except Exception:
                continue
        print(json.dumps(out))
        return
    app, summary, body, cache = sys.argv[1:5]
    paths = records()
    want_app, want_title, want_text = norm(app), norm(summary), norm(body)
    for p in paths:
        n = props(p)
        if norm(n.get("appName")) != want_app:
            continue
        title, text = norm(n.get("title")), norm(n.get("text"))
        if not ((text and text == want_text) or (title and title == want_title and (not text or want_text.startswith(text[:40])))):
            continue
        print(json.dumps(described(n, cache)))
        return
    print("{}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("[]" if sys.argv[1:2] == ["--all"] else "{}")   # --all is read as a list
