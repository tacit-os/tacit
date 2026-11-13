"""tacit-install next to Windows, stopped partway, on a made-up disk: python3 next_to_retry.py <tacit-install>. Loads the
installer's own functions with every tool it runs faked over a partition table kept here (no disk is touched), runs its
main() to a failure and checks what is left for Try again."""
import importlib.machinery, importlib.util, io, json, re, sys, types
GB, SS = 10 ** 9, 512
ESP, MSR = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b", "e3c9e316-0b5c-4db8-817d-f92df00215ae"
WINDOWS, RECOVERY = "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7", "de94bba4-06d1-4d40-a16a-bfd50179d6ac"
DISK = "/dev/nvme0n1"
bad = 0


def check(name, ok, got=""):
    global bad
    bad += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}" + ("" if ok or not got else f": {got}"))


def load(stop, mounted=False, renamed=False):
    """The installer with a 512 GB disk of Windows (140 GB in use), stopping where `stop` says."""
    loader = importlib.machinery.SourceFileLoader("tacit_install", sys.argv[1])
    m = importlib.util.module_from_spec(importlib.util.spec_from_loader("tacit_install", loader))
    loader.exec_module(m)
    disk = {"label": "gpt", "device": DISK, "unit": "sectors", "firstlba": 34, "lastlba": 512 * GB // SS - 34, "sectorsize": SS,
            "partitions": [{"node": f"{DISK}p1", "start": 2048, "size": 100 * 10 ** 6 // SS, "type": ESP, "name": "EFI system partition"},
                           {"node": f"{DISK}p2", "start": 2048 + 100 * 10 ** 6 // SS, "size": 16 * 10 ** 6 // SS, "type": MSR, "name": "Microsoft reserved partition"},
                           {"node": f"{DISK}p3", "start": 2048 + 116 * 10 ** 6 // SS, "size": 510 * GB // SS, "type": WINDOWS, "name": "Basic data partition"},
                           {"node": f"{DISK}p4", "start": 2048 + 116 * 10 ** 6 // SS + 510 * GB // SS, "size": 1 * GB // SS, "type": RECOVERY, "name": ""}]}
    ran = []

    def sh(*cmd, inp=None):
        ran.append(cmd)
        parts = disk["partitions"]
        if cmd[:2] == ("sfdisk", "--json"):
            return json.dumps({"partitiontable": disk})
        if cmd[0] == "sfdisk" and "-N" in cmd:      # Windows's partition entry, shrunk
            n = int(cmd[cmd.index("-N") + 1])
            start, size = map(int, inp.strip().split(","))
            next(p for p in parts if p["node"] == f"{DISK}p{n}")["size"] = size
            return ""
        if cmd[0] == "sgdisk" and any(c.startswith("-n") for c in cmd):
            names = {c[2:].split(":", 1)[0]: c.split(":", 1)[1] for c in cmd if c.startswith("-c")}
            for c in cmd:
                if c.startswith("-n"):
                    n, a, b = c[2:].split(":")
                    parts.append({"node": f"{DISK}p{n}", "start": int(a), "size": int(b) - int(a) + 1, "type": "x", "name": names[n]})
                    if renamed and names[n] == "Tacit":
                        parts[-1]["name"] = "Data"
            return ""
        if cmd[0] == "sgdisk" and any(c.startswith("-d") for c in cmd):
            gone = {f"{DISK}p{c[2:]}" for c in cmd if c.startswith("-d")}
            disk["partitions"] = [p for p in parts if p["node"] not in gone]
            return ""
        if cmd[:3] == ("lsblk", "-nro", "MOUNTPOINTS"):
            return "/mnt/tacit\n" if mounted and cmd[3] != f"{DISK}p3" else "\n"
        return ""

    def run(cmd, **kw):
        ran.append(tuple(cmd))
        out = "You might resize at 140000000000 bytes or 140000 MB (freeing 370000 MB).\n" if cmd[0] == "ntfsresize" else ""
        return types.SimpleNamespace(returncode=0, stdout=out if kw.get("text") else out.encode(), stderr="")

    m.sh, m.subprocess = sh, types.SimpleNamespace(run=run)
    m.fstype = lambda dev: {f"{DISK}p1": "vfat", f"{DISK}p3": "ntfs"}.get(dev, "")
    said = []
    m.say = said.append

    def install(d, place, keep, first):
        made = m.make_room(d, keep)
        if stop == "copy":
            raise m.Refused("copying failed: SQUASHFS error: Read on filesystem failed")
        return d, "/efi", made[0], "x64"
    m.install = install
    m.account = lambda answers: None

    def make_default(*a):
        raise m.Refused("the firmware did not take Tacit's boot entry")
    m.make_default = make_default
    first = {"disk": DISK, "place": "next", "keep": 325 * GB}
    sys.stdin = io.StringIO(json.dumps(first) + "\n" + json.dumps({"answers": {"name": "Sam", "password": "pw"}}) + "\n")
    err, sys.stderr = sys.stderr, io.StringIO()
    try:
        m.main()
        log = sys.stderr.getvalue()
    finally:
        sys.stderr = err
    return m, disk, said, ran, log


def tacit_parts(disk):
    return [p["node"] for p in disk["partitions"] if p["name"] in ("Tacit", "Tacit boot", "Data")]


def windows_size(disk):
    return next(p["size"] for p in disk["partitions"] if p["node"] == f"{DISK}p3") * SS


m, disk, said, ran, log = load("copy")
check("it stops at the copy, and says the disk was changed",
      said and said[-1]["state"] == "failed" and said[-1]["untouched"] is False, str(said[-1:]))
check("Windows keeps the size it was shrunk to", 325 * GB - 2 ** 20 < windows_size(disk) <= 325 * GB, f"{windows_size(disk) / GB:.1f} GB")
check("the two partitions this run made are gone", tacit_parts(disk) == [], f"left: {tacit_parts(disk)}; {log.strip()}")
room = max((b - a + 1) * SS for a, b in m.gaps(disk))
check("the free room they held is back for Try again", room >= m.MIN_TACIT, f"biggest free stretch {room / GB:.0f} GB")
shrinks = sum(1 for c in ran if c[0] == "ntfsresize")
try:
    m.make_room(DISK, None)
    again = ""
except m.Refused as e:
    again = str(e)
check("Try again in the free room (setupd's plan: no keep) makes Tacit's partitions without shrinking Windows again",
      again == "" and sum(1 for c in ran if c[0] == "ntfsresize") == shrinks and len(tacit_parts(disk)) == 2, again)

m, disk, said, ran, log = load("default")
check("stopped while Tacit is made what the computer starts: its partitions stay",
      said[-1]["state"] == "failed" and len(tacit_parts(disk)) == 2, f"left: {tacit_parts(disk)}")
m, disk, said, ran, log = load("copy", mounted=True)
check("one of them still mounted: both stay", len(tacit_parts(disk)) == 2, f"left: {tacit_parts(disk)}; {log.strip()}")
m, disk, said, ran, log = load("copy", renamed=True)
check("one at Tacit's number that is not the one made: both stay", len(tacit_parts(disk)) == 2, f"left: {tacit_parts(disk)}; {log.strip()}")
print(f"{'all' if not bad else bad} {'as they should be' if not bad else 'not as they should be'}")
sys.exit(1 if bad else 0)
