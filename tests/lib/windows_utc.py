"""windows-utc and tacit-install's windows_clock() on made-up Windows partitions: python3 windows_utc.py <scripts/setup>.
Each partition is a folder with a registry hive written here (regf: the base block, one hive bin of key, list and value
cells), read through a pretend ntfscat and lsblk that are the only commands on PATH; no disk is read and nothing is
mounted. Like ntfs-3g's, the pretend ntfscat refuses a volume marked for a check (ntfsprogs/utils.c utils_mount_volume)
unless given -f. windows_clock() writes /etc/adjtime into a throwaway root."""
import importlib.machinery, importlib.util, os, shutil, subprocess, sys, tempfile
setup = sys.argv[1]
bad = 0
DWORD, QWORD = 4, 11


def regf(tree, lists="lf", utf16=False):
    """A hive file holding tree: {key name: {...}} for keys, {value name: (type, bytes)} for values. lists is the kind of
    subkey list every key gets ("ri" is two lh lists under one ri); utf16 stores key names as UTF-16, not ASCII."""
    body = bytearray(b"hbin" + bytes(28))

    def put(data):
        off, size = len(body), -(-(len(data) + 4) // 8) * 8
        body.extend((-size).to_bytes(4, "little", signed=True) + data + bytes(size - 4 - len(data)))
        return off

    def n16(n):
        return n.to_bytes(2, "little")

    def n32(n):
        return n.to_bytes(4, "little")

    def sublist(kind, offs):
        if kind == "ri":
            half = len(offs) // 2 or 1
            return put(b"ri" + n16(2) + n32(sublist("lh", offs[:half])) + n32(sublist("lh", offs[half:])))
        return put(kind.encode() + n16(len(offs)) + b"".join(n32(o) + (b"" if kind == "li" else b"\0\0\0\0") for o in offs))

    def key(name, node, flags=0):
        subs = [key(n, c) for n, c in node.items() if isinstance(c, dict)]
        vks = []
        for vn, (typ, data) in ((n, v) for n, v in node.items() if not isinstance(v, dict)):
            size, at = (0x80000000 | len(data), int.from_bytes(data.ljust(4, b"\0"), "little")) if len(data) <= 4 else (len(data), put(data))
            vks.append(put(b"vk" + n16(len(vn)) + n32(size) + n32(at) + n32(typ) + n16(1) + n16(0) + vn.encode("latin-1")))
        raw = name.encode("utf-16-le" if utf16 else "latin-1")
        nk = bytearray(0x4C)
        nk[0:4] = b"nk" + n16(flags | (0 if utf16 else 0x20))
        nk[0x14:0x20] = n32(len(subs)) + n32(0) + n32(sublist(lists, subs) if subs else 0xFFFFFFFF)
        nk[0x24:0x2C] = n32(len(vks)) + n32(put(b"".join(map(n32, vks))) if vks else 0xFFFFFFFF)
        nk[0x48:0x4A] = n16(len(raw))
        return put(bytes(nk) + raw)

    root = key("ROOT", tree, flags=0x04 | 0x08)
    body[8:12] = n32(len(body))
    base = bytearray(4096)
    base[0:4], base[0x24:0x28] = b"regf", n32(root)
    return bytes(base) + bytes(body)


def system(rtiu=None, current=1, at=None, **kw):
    """A SYSTEM hive whose control set `at` (the current one unless said) has RealTimeIsUniversal = rtiu (type, bytes)."""
    tz = {"TimeZoneKeyName": (1, "W. Europe Standard Time\0".encode("utf-16-le"))}
    if rtiu:
        tz["RealTimeIsUniversal"] = rtiu
    sets = {f"ControlSet{n:03d}": {"Control": {"TimeZoneInformation": dict(tz) if n == (at or current) else
                                               {"TimeZoneKeyName": tz["TimeZoneKeyName"]}}} for n in (1, 2)}
    return regf(dict({"MountedDevices": {}, "Select": {"Current": (DWORD, current.to_bytes(4, "little"))}}, **sets), **kw)


def check(name, ok, got=""):
    global bad
    bad += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}" + ("" if ok or not got else f": {got}"))


ON = (DWORD, (1).to_bytes(4, "little"))
work = tempfile.mkdtemp()
try:
    def computer(parts, tools=("ntfscat", "lsblk")):
        """parts: {"nvme0n1p3": ("ntfs", hive or None, path[, "check"])}, "check" for a volume marked for a check (as
        ntfsresize leaves it); a fresh pretend computer, its PATH returned. Each read is noted in calls beside it."""
        d = tempfile.mkdtemp(dir=work)
        bin_ = os.path.join(d, "bin")
        os.makedirs(bin_)
        lines = []
        for dev, (fs, hive, path, *marked) in parts.items():
            lines.append(f"/dev/{dev} {fs}")
            if hive is not None:
                f = os.path.join(d, dev, path)
                os.makedirs(os.path.dirname(f))
                open(f, "wb").write(hive)
            if marked:
                os.makedirs(os.path.join(d, dev), exist_ok=True)
                open(os.path.join(d, dev, ".check"), "w").close()
        scripts = {"ntfscat": f'force=\n[ "$1" = -f ] && {{ force=1; shift; }}\n'
                              f'[ -e "{d}/${{1##*/}}/.check" ] && [ -z "$force" ] && {{ echo "Volume is scheduled for check." >&2; exit 1; }}\n'
                              f'f="{d}/${{1##*/}}/$2"\n[ -f "$f" ] || {{ echo "ntfscat: $2 not found" >&2; exit 1; }}\n'
                              f'echo "read $1" >> "{d}/calls"\nexec {shutil.which("cat")} "$f"\n',
                   "lsblk": f'[ "$*" = "-nrpo NAME,FSTYPE" ] || exit 1\nprintf "%s\\n" {" ".join(repr(l) for l in lines)}\n'}
        for t in tools:
            open(os.path.join(bin_, t), "w").write("#!/bin/bash\n" + scripts[t])
            os.chmod(os.path.join(bin_, t), 0o755)
        return bin_

    def utc(parts, *args, tools=("ntfscat", "lsblk")):
        bin_ = computer(parts, tools)
        return subprocess.run([sys.executable, "-I", os.path.join(setup, "windows-utc"), *args], env={"PATH": bin_},
                              capture_output=True, text=True).returncode

    HIVE = "Windows/System32/config/SYSTEM"
    for name, parts, want in [
        ("Windows set to UTC (RealTimeIsUniversal DWORD 1): UTC", {"nvme0n1p3": ("ntfs", system(ON), HIVE)}, 0),
        ("set as a QWORD 1, as some guides give it: UTC", {"nvme0n1p3": ("ntfs", system((QWORD, (1).to_bytes(8, "little"))), HIVE)}, 0),
        ("Windows as it comes (no RealTimeIsUniversal): local time", {"nvme0n1p3": ("ntfs", system(), HIVE)}, 1),
        ("RealTimeIsUniversal 0: local time", {"nvme0n1p3": ("ntfs", system((DWORD, bytes(4))), HIVE)}, 1),
        ("set only in a control set Windows does not start with: local time", {"sda2": ("ntfs", system(ON, current=1, at=2), HIVE)}, 1),
        ("set in the one it starts with, ControlSet002: UTC", {"sda2": ("ntfs", system(ON, current=2), HIVE)}, 0),
        ("keys in li lists: read", {"sda2": ("ntfs", system(ON, lists="li"), HIVE)}, 0),
        ("keys in an ri list of lists: read", {"sda2": ("ntfs", system(ON, lists="ri"), HIVE)}, 0),
        ("key names stored as UTF-16: read", {"sda2": ("ntfs", system(ON, utf16=True), HIVE)}, 0),
        ("an older Windows's lower-case system32: read", {"sda2": ("ntfs", system(ON), "Windows/system32/config/SYSTEM")}, 0),
        ("Windows beside its Recovery partition and a games drive: UTC",
         {"nvme0n1p4": ("ntfs", None, HIVE), "nvme0n1p3": ("ntfs", system(ON), HIVE), "sda1": ("ntfs", None, HIVE)}, 0),
        ("two Windows, one in local time: local time",
         {"nvme0n1p3": ("ntfs", system(ON), HIVE), "sda2": ("ntfs", system(), HIVE)}, 1),
        ("two Windows, both in UTC: UTC", {"nvme0n1p3": ("ntfs", system(ON), HIVE), "sda2": ("ntfs", system(ON), HIVE)}, 0),
        ("a BitLocker Windows (not NTFS to lsblk), nothing read: local time", {"nvme0n1p3": ("BitLocker", system(ON), HIVE)}, 1),
        ("a damaged hive: not read, local time", {"nvme0n1p3": ("ntfs", system(ON)[:4200], HIVE)}, 1),
        ("no Windows at all: local time", {"sda1": ("ext4", None, HIVE)}, 1),
        ("Windows set to UTC, marked for a check as ntfsresize leaves it: UTC", {"nvme0n1p3": ("ntfs", system(ON), HIVE, "check")}, 0),
    ]:
        got = utc(parts)
        check(name, got == want, f"exit {got}, wanted {want}")
    got = utc({"nvme0n1p3": ("ntfs", system(ON), HIVE), "sda2": ("ntfs", system(), HIVE)}, "/dev/nvme0n1p3")
    check("only the partitions given are read", got == 0, f"exit {got}")
    got = utc({"nvme0n1p3": ("ntfs", system(ON), HIVE)}, tools=("lsblk",))
    check("no ntfscat: cannot look (2)", got == 2, f"exit {got}")
    bin_ = computer({"nvme0n1p3": ("ntfs", system(ON), HIVE, "check")})
    r = subprocess.run([os.path.join(bin_, "ntfscat"), "/dev/nvme0n1p3", HIVE], capture_output=True)
    check("the pretend ntfscat refuses a volume marked for a check without -f, as ntfs-3g's does", r.returncode == 1 and not r.stdout,
          f"exit {r.returncode}")

    # tacit-install's windows_clock(), with windows-utc beside it as on the stick
    loader = importlib.machinery.SourceFileLoader("tacit_install", os.path.join(setup, "tacit-install"))
    spec = importlib.util.spec_from_loader("tacit_install", loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    clock = getattr(m, "windows_clock", None) or getattr(m, "local_clock")
    for name, parts, want in [
        ("an install next to a Windows set to UTC keeps the clock in UTC", {"nvme0n1p3": ("ntfs", system(ON), HIVE)}, "UTC"),
        ("an install next to Windows as it comes keeps it in local time", {"nvme0n1p3": ("ntfs", system(), HIVE)}, "LOCAL"),
        ("Windows not readable: local time, Windows's default", {"nvme0n1p3": ("BitLocker", None, HIVE)}, "LOCAL"),
        ("Try again after an install that shrank a Windows set to UTC, still marked for a check: UTC",
         {"nvme0n1p3": ("ntfs", system(ON), HIVE, "check")}, "UTC"),
    ]:
        m.TARGET = tempfile.mkdtemp(dir=work)
        os.makedirs(f"{m.TARGET}/etc")
        os.environ["PATH"] = computer(parts) + ":" + os.path.dirname(sys.executable)
        clock()
        got = open(f"{m.TARGET}/etc/adjtime").read()
        check(name, got == f"0.0 0 0\n0\n{want}\n", repr(got))

    # make_room() next to a Windows set to UTC that it shrinks, the disk's tools pretend: shrink_windows() marks the
    # volume for a check, as ntfsresize does. The clock is read before that, and windows_clock() keeps the answer.
    bin_ = computer({"nvme0n1p3": ("ntfs", system(ON), HIVE)})
    d = os.path.dirname(bin_)
    os.environ["PATH"] = bin_ + ":" + os.path.dirname(sys.executable)
    win = {"node": "/dev/nvme0n1p3", "type": m.WINDOWS_DATA, "start": 1050624, "size": 400_000_000}
    t = {"label": "gpt", "sectorsize": 512, "partitions": [{"node": "/dev/nvme0n1p1", "type": m.ESP, "start": 2048, "size": 1048576}, win]}

    def shrunk(disk, w, sectors, ss):
        open(os.path.join(d, "nvme0n1p3", ".check"), "w").close()
        open(os.path.join(d, "calls"), "a").write("shrink\n")
    m.table, m.fstype, m.sh = (lambda disk: t), (lambda dev: "ntfs" if dev == win["node"] else "vfat"), (lambda *cmd, inp=None: "")
    m.windows_shrink, m.shrink_windows = (lambda t, keep: (win, 200_000_000)), shrunk
    m.gaps = lambda t: [(201_050_624, 400_000_000)]
    m.make_room("/dev/nvme0n1", 200_000_000 * 512)
    m.TARGET = tempfile.mkdtemp(dir=work)
    os.makedirs(f"{m.TARGET}/etc")
    clock()
    got = open(f"{m.TARGET}/etc/adjtime").read()
    calls = open(os.path.join(d, "calls")).read().split("\n")[:-1] if os.path.exists(os.path.join(d, "calls")) else []
    check("an install that shrinks a Windows set to UTC keeps the clock in UTC, read before the shrink",
          got == "0.0 0 0\n0\nUTC\n" and calls == ["read /dev/nvme0n1p3", "shrink"], f"{got!r}, {calls}")
finally:
    shutil.rmtree(work, ignore_errors=True)
sys.exit(1 if bad else 0)
