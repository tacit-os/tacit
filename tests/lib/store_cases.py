"""Apps' helpers (scripts/store/bundle.py and stored.py) in a home of their own: python3 -I store_cases.py <tree> <case>
prints what the case saw, as JSON. Nothing is downloaded, installed or started, and the shell is never called: what would
do so is replaced first."""
import fcntl, importlib.util, io, json, os, shutil, sys, tarfile, tempfile, time
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


CASES = {"yours": yours, "remove-open": remove_open, "fake-install": fake_install, "progress": progress,
         "start-newer": lambda: start_after_update("1:0.0.112-1"), "start-same": lambda: start_after_update("1:0.0.111-1"),
         "start-newer-offline": lambda: start_after_update("1:0.0.112-1", offline=True)}
try:
    seen = CASES[case]()
    if seen is not None:
        print(json.dumps(seen))
finally:
    shutil.rmtree(home, ignore_errors=True)
