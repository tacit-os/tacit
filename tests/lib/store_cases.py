"""Apps' helpers (scripts/store/bundle.py and stored.py) in a home of their own: python3 -I store_cases.py <tree> <case>
prints what the case saw, as JSON. Nothing is downloaded, installed or started, and the shell is never called: what would
do so is replaced first."""
import fcntl, hashlib, importlib.util, io, json, os, shutil, sys, tarfile, tempfile, time
sys.dont_write_bytecode = True   # nothing left beside the scripts in the tree
tree, case = sys.argv[1], sys.argv[2]
home = tempfile.mkdtemp(prefix="tacit-store-")
# the launcher database is the person's own: a helper that updates it finds a stand-in first on PATH
bin_ = os.path.join(home, "bin"); os.makedirs(bin_)
open(os.path.join(bin_, "update-desktop-database"), "w").write("#!/bin/sh\nexit 0\n"); os.chmod(os.path.join(bin_, "update-desktop-database"), 0o755)
os.environ.update(HOME=home, XDG_RUNTIME_DIR=os.path.join(home, "run"), PATH=bin_ + os.pathsep + os.environ.get("PATH", ""))
for k in ("DBUS_SESSION_BUS_ADDRESS", "DISPLAY", "XDG_CACHE_HOME", "TACIT_SHELL"):
    os.environ.pop(k, None)


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(tree, "scripts/store", name + ".py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


def yours():
    """the backend's facts for Your apps: GIMP installed with pacman, and an app got here as a bundle"""
    s = load("stored")
    ed = {"apps": {}}
    return {"pacman": s.info("gimp", {}, ed, {"gimp"}, {"gimp"}, set()),
            "bundle": s.info("krita", {}, ed, {"krita"}, {"krita"}, {"krita"})}


def remove_open():
    """Remove pressed on a bundle got here (Blender) while a copy of it is open, then again once it is closed: the backend's
    answers, and what was left each time. The open copy holds the app's lock as run() does, shared"""
    b, s = load("bundle"), load("stored")
    base = os.path.join(b.ROOT, "blender"); os.makedirs(os.path.join(base, "root/usr/bin"))
    launcher = os.path.join(b.APPS_DIR, "blender.desktop"); os.makedirs(b.APPS_DIR)
    open(launcher, "w").write("[Desktop Entry]\nX-Tacit-Bundle=blender\n")
    json.dump(dict(package="blender", version="1", versions={"blender": "1"}, made=[launcher], size=0),
              open(os.path.join(base, "manifest.json"), "w"))
    said = []; s.out = said.append
    running = b.app_lock("blender", fcntl.LOCK_SH)
    s.remove("blender")
    kept = os.path.isdir(os.path.join(base, "root/usr/bin")) and os.path.exists(launcher)
    os.close(running)
    s.remove("blender")
    return {"open": said[0], "kept": kept, "closed": said[1], "gone": not os.path.exists(base) and not os.path.exists(launcher)}


class Started(Exception):
    pass


def start_after_update(listed, offline=False):
    """Discord got here, started for the first time since the system was updated: glibc, the one system package it
    shares, is the same version as when it was got, and the system's lists (pacman's own, which Tacit's updates keep
    fresh) give Discord at `listed`. What run() did before starting it: installs, list refreshes, what it told the shell.
    Offline: its own list is an old one and no mirror answers"""
    b = load("bundle")
    local = os.path.join(home, "local", "glibc-2.42-1"); os.makedirs(local)
    open(os.path.join(local, "desc"), "w").write("%NAME%\nglibc\n\n%VERSION%\n2.42-1\n")
    sync = os.path.join(home, "sync"); os.makedirs(sync)
    with tarfile.open(os.path.join(sync, "extra.db"), "w:gz") as t:
        desc = f"%NAME%\ndiscord\n\n%VERSION%\n{listed}\n\n%FILENAME%\ndiscord-{listed}-x86_64.pkg.tar.zst\n\n%DEPENDS%\nglibc\n".encode()
        m = tarfile.TarInfo(f"discord-{listed}/desc"); m.size = len(desc); t.addfile(m, io.BytesIO(desc))
    b.LOCAL_DB, b.SYSTEM_SYNC, b.repos = os.path.dirname(local), sync, lambda: [("extra", [])]
    base = os.path.join(b.ROOT, "discord"); os.makedirs(os.path.join(base, "root/usr/bin"))
    json.dump(dict(package="discord", version="1:0.0.111-1", versions={"discord": "1:0.0.111-1"}, shared=["glibc"],
                   host_versions={"glibc": "2.42-1"}, host_stamp=1, ids=[], exec=["/usr/bin/discord"], made=[], size=0),
              open(os.path.join(base, "manifest.json"), "w"))
    seen = {"installed": [], "lists": [], "told": []}
    b.install = lambda pkg, quiet=False, step=None: seen["installed"].append(pkg)
    if offline:
        os.makedirs(os.path.join(b.CACHE, "sync")); shutil.copy(os.path.join(sync, "extra.db"), os.path.join(b.CACHE, "sync"))
    else:
        b.refresh_sync = lambda max_age=3600: seen["lists"].append(max_age)
    b.tell = lambda *a: seen["told"].append(list(a))
    b.user_dirs = lambda: []
    def started(path, argv):
        raise Started()
    b.os.execvp = started
    try:
        b.run("discord", [])
    except Started:
        pass
    seen["host_stamp"] = json.load(open(os.path.join(base, "manifest.json")))["host_stamp"] == b.host_stamp()
    seen["tried"] = os.path.exists(os.path.join(b.RUN, "discord.tried"))
    return seen


class Unpacked(Exception):
    pass


def fake_install():
    """bundle.py install blender as the store runs it, its lines on stdout: Blender's 3 MB package comes slowly (a third a
    little over every second), blender-data's 1 MB at once. Its own install(); what it downloads and unpacks is replaced,
    and it ends where unpacking would start"""
    b = load("bundle")
    pkg = lambda n, mb: dict(name=n, version="4.5-1", filename=f"{n}-4.5-1-x86_64.pkg.tar.zst", csize=mb * 1_000_000, isize=1000,
                             depends=[], provides=[], sha256="", repo="extra", servers=[])
    bundle = {"blender": pkg("blender", 3), "blender-data": pkg("blender-data", 1)}
    b.refresh_sync = lambda max_age=3600: None
    b.resolve = lambda target: (bundle, [])
    def fetch(p):
        d = os.path.join(b.CACHE, "pkg"); os.makedirs(d, exist_ok=True)
        dst = os.path.join(d, p["filename"])
        with open(dst + ".part", "wb") as f:
            for i in range(p["csize"] // 1_000_000):
                if i:
                    time.sleep(1.2)
                f.write(b"\0" * 1_000_000); f.flush()
        os.replace(dst + ".part", dst)
        return dst
    b.fetch = fetch
    def members(path):
        raise Unpacked()
    b.members = members
    try:
        b.install("blender")
    except Unpacked:
        pass


def progress():
    """the store's backend getting Blender as a bundle (stored.py bundle_install) over fake_install: what it tells the window"""
    s = load("stored")
    s.BUNDLE = [sys.executable, "-I", os.path.abspath(__file__), tree, "fake-install"]
    said = []; s.out = said.append
    s.bundle_install("blender")
    return said


def can():
    """what an app's page is told it can use (stored.py info's "can"), for apps offered for calls and one with none"""
    s = load("stored")
    ed = {"apps": {}}
    return {p: s.info(p, {}, ed, {p}, set(), set()).get("can") for p in ("signal-desktop", "telegram-desktop", "discord", "element-desktop", "obs-studio", "gimp")}


def restart_mark():
    """Get X and the updates (stored.py install_ with everything) and a plain Get through pacman, with pacman's run
    replaced by one that succeeds: whether each left the restart mark, and what the backend says of it before and after the
    computer restarts (another boot id)"""
    s = load("stored")
    boot = os.path.join(home, "boot_id"); open(boot, "w").write("aaaa\n")
    s.BOOT_ID = boot
    s.out = lambda obj: None
    s.installed = lambda: set()
    s.bundle_install = lambda pkg: "system"
    s.system_plan = lambda pkg, inst: {"can": True, "count": 1}

    class Pacman:
        def __init__(self, *a, **k):
            self.stdout = iter(["Packages (1) krita-5.2", "(1/1) installing krita"])
        def wait(self):
            return 0
    s.subprocess.Popen = Pacman
    seen = {}
    s.install_("krita", everything=False)
    seen["plain"] = s.restart_needed() if hasattr(s, "restart_needed") else None
    s.install_("krita", everything=True)
    seen["everything"] = s.restart_needed() if hasattr(s, "restart_needed") else None
    seen["mark"] = os.path.exists(os.path.join(home, ".local/state/tacit/restart-needed"))
    open(boot, "w").write("bbbb\n")
    seen["after restart"] = s.restart_needed() if hasattr(s, "restart_needed") else None
    return seen


def version():
    """the Version an app's page is told (stored.py info), the lists giving newer ones than the bundles got here (Krita
    5.2.1, Discord 0.0.111 with an epoch) and for GIMP, installed with pacman, and Pinta, not installed"""
    s = load("stored")
    for pkg, v in (("krita", "5.2.1-1"), ("discord", "1:0.0.111-1")):
        os.makedirs(os.path.join(s.BUNDLES, pkg))
        json.dump(dict(package=pkg, version=v, versions={pkg: v}, ids=[pkg]), open(os.path.join(s.BUNDLES, pkg, "manifest.json"), "w"))
    ed, listed = {"apps": {}}, {"krita": "5.2.3", "discord": "0.0.112", "gimp": "3.0.4", "pinta": "2.1"}
    inst = {"krita", "discord", "gimp"}
    return {p: s.info(p, {}, ed, set(listed), inst, {"krita", "discord"}, {"version": v})["version"] for p, v in listed.items()}


# curl on a line that moves LINE_BPS bytes a second, ended by its own limits on a clock of its own (nothing waits): the file
# LINE_FILE, said to be LINE_SIZE bytes, arrives whole unless a limit ends the try first, which leaves a part and code 28.
# LINE_BPS 0 is a mirror that never answers. Each try's end goes to LINE_LOG as "<seconds> <code>"
CURL_ON_A_LINE = r'''#!/usr/bin/env python3
import os, shutil, sys
a = sys.argv[1:]
opt = lambda k, d: float(a[a.index(k) + 1]) if k in a else d
bps, out = float(os.environ["LINE_BPS"]), a[a.index("-o") + 1]
cap, size = opt("--max-time", float("inf")), float(os.environ["LINE_SIZE"])
if not bps:
    took, code = min(opt("--connect-timeout", 300), cap), 28          # libcurl waits 300 s to connect unless told
elif "--speed-limit" in a and bps < opt("--speed-limit", 0):
    took, code = min(opt("--speed-time", 30), cap), 28
else:
    took, code = (size / bps, 0) if size / bps <= cap else (cap, 28)
if code:
    open(out, "wb").write(b"\0" * 100)
else:
    shutil.copy(os.environ["LINE_FILE"], out)
open(os.environ["LINE_LOG"], "a").write(f"{took:g} {code}\n")
sys.exit(code)
'''


def lists_on_a_line(bps):
    """Apps' own package lists fetched for the first time (none kept yet) over a line of `bps` bytes a second, Arch's extra
    list being 9 MB, as before an install: whether it came whole or the fetch said why not, and when each try ended"""
    b = load("bundle")
    src = os.path.join(home, "extra.db")
    with tarfile.open(src, "w:gz") as t:
        desc = b"%NAME%\nkrita\n\n%VERSION%\n5.2.3-1\n\n%FILENAME%\nkrita-5.2.3-1-x86_64.pkg.tar.zst\n"
        m = tarfile.TarInfo("krita-5.2.3-1/desc"); m.size = len(desc); t.addfile(m, io.BytesIO(desc))
    curl = os.path.join(bin_, "curl"); open(curl, "w").write(CURL_ON_A_LINE); os.chmod(curl, 0o755)
    log = os.path.join(home, "line.log")
    os.environ.update(LINE_BPS=str(bps), LINE_FILE=src, LINE_SIZE="9000000", LINE_LOG=log)
    b.repos = lambda: [("extra", ["https://mirror.example/extra/os/x86_64"])]
    try:
        b.refresh_sync(max_age=600)
        said = "ok" if b.load_sync()[0].get("krita", {}).get("version") == "5.2.3-1" else "not the list"
    except b.Refused as e:
        said = e.why
    return {"said": said, "tries": [[float(s), int(c)] for s, c in (l.split() for l in open(log))] if os.path.exists(log) else []}


# a mirror that has MIRROR_FILE. Asked to go on (-C -) from part of it already here, it does when MIRROR_RESUMES is set and
# answers that it cannot (curl's 33) otherwise. Each call's arguments go to MIRROR_LOG, a JSON line each
CURL_MIRROR = r'''#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
out, url = a[a.index("-o") + 1], a[-1]
open(os.environ["MIRROR_LOG"], "a").write(json.dumps(a) + "\n")
if url.endswith(".sig"):
    open(out, "w").write("signature"); sys.exit(0)
whole = open(os.environ["MIRROR_FILE"], "rb").read()
have = os.path.getsize(out) if "-C" in a and os.path.exists(out) else 0
if have and not os.environ.get("MIRROR_RESUMES"):
    sys.exit(33)
open(out, "ab" if have else "wb").write(whole[have:])
'''


def fetch_again(resumes):
    """Blender's package fetched again after a first try stopped a third of the way, from Tacit's one mirror, which can or
    cannot resume: what fetch() gave (the whole package, checked, or why not) and the calls to curl, as (resumed?, file)"""
    b = load("bundle")
    whole = os.urandom(600_000)
    src = os.path.join(home, "blender.pkg"); open(src, "wb").write(whole)
    for name, text in (("curl", CURL_MIRROR), ("gpgv", "#!/bin/sh\nexit 0\n")):
        open(os.path.join(bin_, name), "w").write(text); os.chmod(os.path.join(bin_, name), 0o755)
    log = os.path.join(home, "mirror.log")
    os.environ.update(MIRROR_FILE=src, MIRROR_LOG=log, MIRROR_RESUMES="1" if resumes else "")
    p = dict(filename="blender-4.5-1-x86_64.pkg.tar.zst", sha256=hashlib.sha256(whole).hexdigest(), servers=["https://mirror.example/extra/os/x86_64"])
    d = os.path.join(b.CACHE, "pkg"); os.makedirs(d)
    open(os.path.join(d, p["filename"] + ".part"), "wb").write(whole[:200_000])
    try:
        said = "ok" if open(b.fetch(p), "rb").read() == whole else "not the package"
    except b.Refused as e:
        said = e.why
    return {"said": said, "calls": [["-C" in c, c[-1].rsplit("/", 1)[-1]] for c in (json.loads(l) for l in open(log))] if os.path.exists(log) else []}


CASES = {"yours": yours, "can": can, "version": version, "restart-mark": restart_mark, "remove-open": remove_open, "fake-install": fake_install, "progress": progress,
         "lists-slow": lambda: lists_on_a_line(125_000), "lists-stalled": lambda: lists_on_a_line(500), "lists-dead": lambda: lists_on_a_line(0),
         "fetch-no-resume": lambda: fetch_again(False), "fetch-resume": lambda: fetch_again(True),
         "start-newer": lambda: start_after_update("1:0.0.112-1"), "start-same": lambda: start_after_update("1:0.0.111-1"),
         "start-newer-offline": lambda: start_after_update("1:0.0.112-1", offline=True)}
try:
    seen = CASES[case]()
    if seen is not None:
        print(json.dumps(seen))
finally:
    shutil.rmtree(home, ignore_errors=True)
