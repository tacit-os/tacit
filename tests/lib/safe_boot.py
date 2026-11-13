"""tacit-install's boot entries over a throwaway root: python3 safe_boot.py <tacit-install>.
Runs the installer's own boot_entries() and make_default() (no disk, bootctl or firmware is touched) and checks that
"Tacit (safe start)" sits beside tacit.conf with its root and resume and only the options Tacit needs, and that
loader.conf still starts tacit.conf with editing off."""
import fnmatch, importlib.machinery, importlib.util, inspect, os, shutil, sys, tempfile
sys.dont_write_bytecode = True
src = open(sys.argv[1]).read()
if "def boot_entries(" not in src:
    print("FAIL tacit-install writes tacit.conf only: a kernel option that stops the start needs the stick to undo (1.2.14)")
    sys.exit(1)
loader = importlib.machinery.SourceFileLoader("tacit_install", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("tacit_install", loader))
loader.exec_module(m)

QUIET = "quiet splash loglevel=1 rd.udev.log_level=0 udev.log_level=0 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0"
bad = 0


def check(name, ok, got=""):
    global bad
    bad += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}" + ("" if ok or not got else f": {got!r}"))


def entry(path):
    """An entry's keys, and its options as words."""
    keys = {}
    for line in open(path).read().splitlines():
        k, _, v = line.partition(" ")
        keys[k] = v
    return keys, keys.get("options", "").split()


work = tempfile.mkdtemp()
try:
    for name, partuuid, offset, resume in [
        ("with a swap file", "aaaa-root", 2621696, ["resume=PARTUUID=aaaa-root", "resume_offset=2621696"]),
        ("with no swap file (too little room)", "bbbb-root", None, []),
    ]:
        m.TARGET = tempfile.mkdtemp(dir=work)
        m.boot_entries(partuuid, offset)
        d = f"{m.TARGET}/boot/loader/entries"
        tacit, words = entry(f"{d}/tacit.conf")
        check(f"{name}: tacit.conf as before", (tacit["title"], words) == ("Tacit", [f"root=PARTUUID={partuuid}", "rw", *QUIET.split(), *resume]),
              tacit)
        if not os.path.exists(f"{d}/tacit-safe.conf"):
            check(f"{name}: a safe start entry beside tacit.conf", False, sorted(os.listdir(d)))
            continue
        safe, words = entry(f"{d}/tacit-safe.conf")
        check(f"{name}: the safe entry is called Tacit (safe start)", safe.get("title") == "Tacit (safe start)", safe.get("title"))
        check(f"{name}: it starts the same kernel and initramfs as tacit.conf",
              (safe.get("linux"), safe.get("initrd")) == (tacit["linux"], tacit["initrd"]) == ("/vmlinuz-linux", "/initramfs-linux.img"), safe)
        check(f"{name}: its options are root, rw" + (" and resume" if resume else "") + ", nothing else (no quiet or splash)",
              words == [f"root=PARTUUID={partuuid}", "rw", *resume], words)
        check(f"{name}: no other file in the entries folder", sorted(os.listdir(d)) == ["tacit-safe.conf", "tacit.conf"], sorted(os.listdir(d)))

    # a reinstall over an earlier Tacit on the same EFI partition: both entries name the new root
    m.boot_entries("cccc-new", None)
    safe, words = entry(f"{m.TARGET}/boot/loader/entries/tacit-safe.conf")
    check("a reinstall writes the safe entry again with the new root", words == ["root=PARTUUID=cccc-new", "rw"], words)

    check("the install writes its boot entries through boot_entries()", "boot_entries(" in inspect.getsource(m.install)
          and "tacit.conf" not in inspect.getsource(m.install))

    # loader.conf (make_default, the firmware's entry left out): tacit.conf stays the default, the menu hidden, editing off
    m.TARGET = tempfile.mkdtemp(dir=work)
    os.makedirs(f"{m.TARGET}/boot/loader")
    m.boot_entry = lambda *a: None
    m.make_default("instead", "/dev/vda", "/boot", "/dev/vda1", "x64")
    conf = open(f"{m.TARGET}/boot/loader/loader.conf").read()
    check("loader.conf starts tacit.conf at once, with editing off", conf == "default tacit.conf\ntimeout 0\neditor no\n", conf)
    default = conf.split()[1]
    check("the safe entry is never the default", fnmatch.fnmatchcase("tacit.conf", default) and not fnmatch.fnmatchcase("tacit-safe.conf", default))
finally:
    shutil.rmtree(work, ignore_errors=True)
print("all as they should be" if not bad else f"{bad} not as they should be")
sys.exit(1 if bad else 0)
