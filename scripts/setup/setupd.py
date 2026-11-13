#!/usr/bin/env python3
# setupd: what Tacit's setup (setup.qml) needs from the computer, as JSON lines on stdin/stdout.
#
# On Tacit's live system (the ISO, /run/archiso) it installs for real: tacit-install (beside this file, run as root
# with sudo) puts Tacit next to what is on the disk shown, or erases it, copies the live system onto it, joins the
# network asked for and makes the account. There it also reads, as root, what "next to" needs: the partition table,
# its free room, and how small Windows can go. Anywhere else it is a PRACTICE run: it reads the computer and plays the install, but writes to no disk,
# joins no network and creates no account.
#
# TACIT_SETUP_SCENARIO=windows|bitlocker|asleep|nouefi|full|empty|small|linux|linuxroom  shows a disk case this computer does not have
#                     two                                   two disks: Windows on one, the other empty
#                     check|unread                          Windows with a disk check waiting, or a partition not read
# TACIT_SETUP_FAIL=1                                       the practice install stops at 60 %
# TACIT_SETUP_SECONDS=90                                    how long the practice install takes
import json, os, re, select, shutil, subprocess, sys, threading, time, traceback

SCENARIO = os.environ.get("TACIT_SETUP_SCENARIO", "")
# the real install only on Tacit's live system, never with a made-up disk
REAL = os.path.isdir("/run/archiso") and not SCENARIO and os.environ.get("TACIT_SETUP_PRACTICE") != "1"
INSTALLER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tacit-install")
FAIL = os.environ.get("TACIT_SETUP_FAIL") == "1"
SECONDS = float(os.environ.get("TACIT_SETUP_SECONDS", "90"))
GB = 1_000_000_000
# Tacit itself is about 7 GB, and the swap file for hibernating is the size of the memory (tacit-install makes it only
# where 20 GB stay free): 32 GB, as for a whole disk. tacit-install refuses less
MIN_TACIT = 32 * GB
WINDOWS_DATA = "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7"
ESP = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
lock = threading.Lock()

def emit(obj):
    with lock:
        sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
        sys.stdout.flush()

def run(*cmd, timeout=10):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return ""

# ------------------------------------------------------------------ languages and keyboards
# the five offered first, then the rest; names in their own language. English is British English with the US keyboard,
# the one most English speakers have (a US keyboard on the UK layout put " on Shift+2: Discord, OYINOS, 2026-11-12)
LANGUAGES = [("en_GB", "English", "us"), ("sv_SE", "Svenska", "se"), ("so_SO", "Soomaali", "us"), ("ar_SA", "العربية", "ara"),
             ("de_DE", "Deutsch", "de"), ("en_US", "English (US)", "us"), ("fr_FR", "Français", "fr"), ("es_ES", "Español", "es"),
             ("it_IT", "Italiano", "it"), ("nl_NL", "Nederlands", "nl"), ("nb_NO", "Norsk bokmål", "no"), ("da_DK", "Dansk", "dk"),
             ("fi_FI", "Suomi", "fi"), ("pl_PL", "Polski", "pl"), ("pt_PT", "Português", "pt"), ("pt_BR", "Português (Brasil)", "br"),
             ("tr_TR", "Türkçe", "tr"), ("fa_IR", "فارسی", "ir"), ("ur_PK", "اردو", "pk"), ("hi_IN", "हिन्दी", "in"),
             ("ru_RU", "Русский", "ru"), ("uk_UA", "Українська", "ua"), ("el_GR", "Ελληνικά", "gr"), ("he_IL", "עברית", "il"),
             ("zh_CN", "中文 (简体)", "cn"), ("ja_JP", "日本語", "jp"), ("ko_KR", "한국어", "kr"), ("am_ET", "አማርኛ", "et"),
             ("sw_KE", "Kiswahili", "ke"), ("ti_ER", "ትግርኛ", "et")]
RTL = {"ar_SA", "fa_IR", "ur_PK", "he_IL"}

def translated(code):
    """Whether Tacit has its words in this language: a table in translations/ for it, or for another of the same language
    (Translation.qml reads pt_BR for pt_PT). Setup says so when not; the installed system is then in English."""
    try:
        have = [f[:-5] for f in os.listdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "translations")) if f.endswith(".json")]
    except OSError:
        return True     # not known: say nothing
    return any(h == code or h.split("_")[0] == code.split("_")[0] for h in have)

# Layouts that cannot type Latin letters (a Wi-Fi name or password, a URL, a command): Setup puts the US layout before
# them, with Alt + Shift to switch (tacit-install writes the pair for the installed system too)
NON_LATIN = {"af", "am", "ara", "bd", "bg", "bt", "by", "eg", "et", "ge", "gr", "il", "in", "iq", "ir", "kg", "kh", "kz", "la",
             "lk", "ma", "mk", "mm", "mn", "mv", "my", "np", "pk", "rs", "ru", "sy", "th", "tj", "ua", "uz"}

def live_keyboard():
    """The layout the live session types with now (Hyprland's main keyboard, as Settings reads it), else the one
    /etc/vconsole.conf names, else US. Setup starts on it: the first language's own layout (UK) took the keys of a US
    keyboard away as Setup opened."""
    code = ""
    try:
        keyboards = json.loads(run("hyprctl", "devices", "-j")).get("keyboards", [])
        code = (next((k for k in keyboards if k.get("main")), None) or keyboards[0]).get("layout", "")
    except (ValueError, IndexError, AttributeError):
        pass
    if not code:
        try:
            m = re.search(r"^XKBLAYOUT=[\"']?([^\"'\s]*)", open("/etc/vconsole.conf").read(), re.M)
            code = m.group(1) if m else ""
        except OSError:
            pass
    first = code.split(",")[0]
    return first if re.fullmatch(r"[a-z]{2,8}", first) else "us"

def layouts():
    out, on = [], False
    try:
        for line in open("/usr/share/X11/xkb/rules/evdev.lst"):
            if line.startswith("! layout"):
                on = True; continue
            if line.startswith("!"):
                if on: break
                continue
            if on and line.strip():
                code, name = line.strip().split(None, 1)
                if code != "custom":        # "A user-defined custom Layout": not something a person picks here
                    out.append({"code": code, "name": name})
    except OSError:
        pass
    return sorted(out, key=lambda l: l["name"])

# ------------------------------------------------------------------ Wi-Fi (read only)
def wifi():
    nets = {}
    for line in run("nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list").splitlines():
        p = [re.sub(r"\\(.)", r"\1", f) for f in re.findall(r"((?:\\.|[^:\\])*)(?::|$)", line)]
        if len(p) < 4 or not p[1]:
            continue
        ssid = p[1]
        # an 802.1X network (a university's, an office's) wants a user name too, which Setup does not ask: Settings joins it
        n = {"ssid": ssid, "signal": int(p[2] or 0), "secure": p[3] not in ("", "--"), "inUse": p[0] == "*",
             "enterprise": bool(re.search(r"802\.1X|EAP", p[3], re.I))}
        if ssid not in nets or n["signal"] > nets[ssid]["signal"]:
            nets[ssid] = n
    return sorted(nets.values(), key=lambda n: (not n["inUse"], -n["signal"]))[:24]

def join_failure(text):
    """Why nmcli did not join: "password" when it says a key was needed and none fitted (its "Secrets were required, but
    not provided" after a wrong one), else "network": out of range, no address, a timeout. Setup tells the two apart."""
    t = text.lower()
    return "password" if "secrets were required" in t or "password" in t else "network"

# A cable that connects this computer (NetworkManager's ethernet device connected): Setup says so instead of "No
# networks found", which is all it said on a cable (the VM test, 2026-10-16)
def wired():
    return any(l.split(":")[1:2] == ["connected"] for l in run("nmcli", "-t", "-f", "TYPE,STATE", "dev").splitlines()
               if l.startswith("ethernet:"))

# The time zone where this computer is, from its internet address (Ubuntu's lookup, which its installer uses for the
# same), set on the live system so Setup's clock is right, and handed to tacit-install; "" offline or for a name the
# system does not have, and the installed system keeps UTC. Every install was UTC until 2026-10-16. Asked at the first
# hello, after a Wi-Fi join and, when still not found, as the answers go to tacit-install; one ask at a time
zone = {"name": ""}
zone_lock = threading.Lock()
def find_zone():
    with zone_lock:
        if zone["name"]:
            return
        m = re.search(r"<TimeZone>([A-Za-z0-9_+/-]+)</TimeZone>", run("curl", "-fsS", "--max-time", "6", "https://geoip.ubuntu.com/lookup", timeout=8))
        if m and os.path.isfile(f"/usr/share/zoneinfo/{m.group(1)}"):
            zone["name"] = m.group(1)
            as_root("timedatectl", "set-timezone", zone["name"])

# ------------------------------------------------------------------ disks (read only)
def as_root(*cmd):
    """A read that needs root: only on the live system, where sudo asks for nothing."""
    if not REAL:
        return None
    try:
        return subprocess.run(["sudo", "-n", *cmd], input="", capture_output=True, text=True, errors="replace", timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None

def gaps(t):
    """The disk's free stretches in sectors, (first, last), starting on a 1 MiB boundary (as tacit-install works them out)."""
    align = max(1, 1024 * 1024 // t["sectorsize"])
    out, at = [], t["firstlba"]
    for start, size in sorted((p["start"], p["size"]) for p in t.get("partitions", [])) + [(t["lastlba"] + 1, 0)]:
        first = -(-at // align) * align
        if start - 1 >= first:
            out.append((first, start - 1))
        at = max(at, start + size)
    return out

def layout(name, parts):
    """What "next to" needs: GPT, an EFI partition, the biggest free stretch; for Windows how small its own partition can
    go, and whether it shut down fully (Fast Startup leaves it hibernated)."""
    r = as_root("sfdisk", "--json", name)
    try:
        t = json.loads(r.stdout)["partitiontable"]
    except (AttributeError, ValueError, KeyError):
        return {}
    gpt = t.get("label") == "gpt"
    # the free room only on GPT, the one table "next to" goes on: an MBR table (an older office PC's) has no first and
    # last usable sector in sfdisk's answer, gaps() failed on it and the whole disk list with it (Reddit, 2026-11-01)
    out = {"gpt": gpt, "esp": any(str(p.get("type", "")).lower() == ESP for p in t.get("partitions", [])),
           "free": max([(b - a + 1) * t["sectorsize"] for a, b in gaps(t)] or [0]) if gpt and "firstlba" in t else 0}
    # Windows is looked at (how small it can go, whether it shut down fully) only where Tacit could go next to it: a GPT
    # disk with an EFI partition. A drive of games or files gets the quick look; reading every NTFS volume on it took
    # most of the time on a PC with several big drives (Discord 2026-11-01)
    if not (gpt and out["esp"]):
        return out
    # the partitions tacit-install checks: Windows data (Recovery and OEM are NTFS too)
    data = {p["node"].rsplit("/", 1)[-1] for p in t["partitions"] if p["type"].lower() == WINDOWS_DATA}
    ntfs = [p for p in parts if p.get("fstype") == "ntfs" and p["name"] in data]
    if ntfs:
        win = max(ntfs, key=lambda p: p["size"])
        node = "/dev/" + win["name"]
        # Fast Startup's image sits on the system volume but caches every NTFS volume, so each one is looked at
        stopped = None
        for p in ntfs:
            n = "/dev/" + p["name"]
            i = as_root("ntfsresize", "--info", "--no-action", n)
            h = as_root("sh", "-c", 'ntfscat "$1" hiberfil.sys 2>/dev/null | head -c 4', "sh", n)
            if i and (i.returncode != 0 or (h and h.stdout.lower() == "hibr")):
                stopped = stopped or (i, h)
            if p is win:
                info = i
        m = re.search(r"You might resize at (\d+) bytes", info.stdout if info else "")
        if stopped:
            out.update(asleep=True, **windows_stopped(*stopped))
        elif m:
            out.update(used=int(m.group(1)), winSize=win["size"])
    return out

def windows_stopped(info, hib):
    """Why Windows' partition cannot be sized now, from ntfsresize's own sentences. Every refusal used to read "Windows
    didn't shut down fully"; a disk check Windows had waiting looked the same (ygnk, 2026-10-30). All it said goes to
    /tmp/tacit-windows.log, and a reason that is none of these is shown in its words."""
    said = "\n".join(s for s in (info.stderr, info.stdout) if s).strip()
    try:
        with open("/tmp/tacit-windows.log", "w") as f:
            f.write(said + "\n")
    except OSError:
        pass
    low = said.lower()
    if (hib and hib.stdout.lower() == "hibr") or re.search(r"hibernat|journal file is unclean|unsafe state|fast restart|windows cache", low):
        return {"why": "asleep"}
    if re.search(r"scheduled for check|chkdsk|inconsistent|dirty", low):
        return {"why": "check"}
    lines = [l.strip() for l in said.splitlines() if l.strip() and not l.startswith("ntfsresize v")]
    return {"why": "other", "says": " ".join(lines[-2:])[:240]}

# the disk picked in Setup's disk list (op "disk"); None until then
chosen = {"name": None}

def all_disks():
    """Every disk inside this computer, each with what is on it. Never the stick setup runs from, nor any USB disk."""
    if SCENARIO:
        return fake_disks(SCENARIO)
    try:
        d = json.loads(run("lsblk", "-J", "-b", "-o", "NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL,TRAN,RM,MOUNTPOINTS,PARTTYPE,PARTLABEL"))
    except ValueError:
        return []
    # the stick itself, however it is attached (a card reader, a VM's disk): the disk under the live system's boot files
    src = run("findmnt", "-nro", "SOURCE", "/run/archiso/bootmnt").strip()
    stick = run("lsblk", "-nrso", "NAME", src).split()[-1:] if src else []
    inside = [b for b in d.get("blockdevices", [])
            if b.get("type") == "disk" and not b.get("rm") and b.get("tran") != "usb" and not b["name"].startswith(("zram", "loop")) and not re.fullmatch(r"mmcblk\d+(boot\d+|rpmb)", b["name"])
            and b["name"] not in stick]
    # each disk read on its own thread: the reads wait on different drives, so the slowest one sets the time, not the sum
    if len(inside) < 2:
        return [described(b) for b in inside]
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=len(inside)) as pool:
        return list(pool.map(described, inside))

def parts_of(b):
    """A disk's partitions for "Choose partitions myself": name, size, what is on it, its label, whether it is an EFI one."""
    return [{"name": "/dev/" + p["name"], "size": p.get("size") or 0, "fstype": p.get("fstype") or "",
             "label": p.get("label") or p.get("partlabel") or "", "esp": (p.get("parttype") or "").lower() == ESP}
            for p in b.get("children") or [] if p.get("type") == "part"]

def described(b):
    """describe(), and a disk it cannot read is still offered, as one whose contents Setup does not know (erasing it is
    still possible): one unreadable disk took the whole list down, and Setup said there was no disk at all. What failed
    goes to /tmp/tacit-setup-disks.log."""
    try:
        return dict(describe(b), parts=parts_of(b))
    except Exception:
        import traceback
        try:
            with open("/tmp/tacit-setup-disks.log", "a") as f:
                f.write(f"{b.get('name')}: " + traceback.format_exc() + "\n")
        except OSError:
            pass
        return {"name": "/dev/" + b["name"], "model": (b.get("model") or "").strip() or "this disk", "size": b.get("size") or 0,
                "case": "other", "parts": parts_of(b)}

def disks(ds=None):
    """The disk Tacit would go on: the one picked, else an empty one (nothing to lose), else the only one; with several
    disks that hold something, none until the person chooses ({"case": "choose"}). It was always the biggest, with no
    choice: with Windows on a big disk and an empty one beside it, Tacit went next to Windows or erased it (a Reddit
    reader, 2026-10-18)."""
    ds = all_disks() if ds is None else ds
    if not ds:
        return {"case": "none"}
    picked = next((d for d in ds if d["name"] == chosen["name"]), None)
    if picked:
        return picked
    empty = [d for d in ds if d["case"] == "empty" and d["size"] >= MIN_TACIT]
    if empty:
        return max(empty, key=lambda d: d["size"])
    if len(ds) == 1:
        return ds[0]
    # several disks with something on them: the person chooses. It was the biggest, which on a PC with a 2 TB game drive
    # was the game drive (Discord 2026-11-01)
    return {"case": "choose"}

def describe(best):
    parts = best.get("children", [])
    fs = [p.get("fstype") or "" for p in parts]
    disk = {"name": "/dev/" + best["name"], "model": (best.get("model") or "").strip() or "this disk", "size": best["size"]}
    if "BitLocker" in fs:
        return dict(disk, case="bitlocker")
    # what Windows uses and the free room need root: a practice run says so rather than guess
    room = layout(disk["name"], parts) if parts else {}
    # Windows is a disk Windows starts from (NTFS and an EFI partition); NTFS alone is a drive of files ("Other files"),
    # which Setup called Windows ("Instead of Windows") on a PC with a game drive. The EFI partition is read from lsblk
    # too, so a practice run (no sfdisk as root) sees it
    if "ntfs" in fs and (room.get("esp") or any((p.get("parttype") or "").lower() == ESP for p in parts)):
        return dict(disk, case="asleep", why=room.get("why", "asleep"), says=room.get("says", "")) if room.get("asleep") \
            else dict(disk, case="windows", **{"used": None, **room})
    if any(f in ("ext4", "btrfs", "xfs", "f2fs") for f in fs):
        return dict(disk, case="linux", **room)
    return dict(disk, case="empty" if not parts and not best.get("fstype") else "other", **room)

def fake_disks(case):
    if case == "two":
        return [dict(fake_disk("windows"), name="/dev/sda", model="Seagate Barracuda", size=1000 * GB, winSize=998 * GB),
                fake_disk("empty")]
    if case == "games":     # a PC like the one in Discord 2026-11-01: Windows, and two drives of games
        return [fake_disk("windows"),
                dict(fake_disk("other"), name="/dev/sda", model="WD Games", size=2000 * GB, esp=False,
                     parts=[{"name": "/dev/sda1", "size": 2000 * GB, "fstype": "ntfs", "label": "Games", "esp": False}]),
                dict(fake_disk("other"), name="/dev/sdb", model="Seagate", size=1000 * GB, esp=False,
                     parts=[{"name": "/dev/sdb1", "size": 600 * GB, "fstype": "ntfs", "label": "Other games", "esp": False},
                            {"name": "/dev/sdb2", "size": 400 * GB, "fstype": "", "label": "", "esp": False}])]
    return [fake_disk(case)]

def fake_disk(case):
    disk = {"name": "/dev/nvme0n1", "model": "Samsung SSD", "size": 512 * GB, "fake": True, "gpt": True, "esp": True, "free": 0,
            "parts": [{"name": "/dev/nvme0n1p1", "size": 100 * 1000 ** 2, "fstype": "vfat", "label": "", "esp": True},
                      {"name": "/dev/nvme0n1p2", "size": 16 * 1000 ** 2, "fstype": "", "label": "", "esp": False},
                      {"name": "/dev/nvme0n1p3", "size": 510 * GB, "fstype": "ntfs", "label": "Windows", "esp": False}]}
    if case == "windows":
        return dict(disk, case="windows", used=140 * GB, winSize=510 * GB)
    if case == "full":
        return dict(disk, case="windows", used=480 * GB, winSize=510 * GB)
    if case == "linuxroom":
        return dict(disk, case="linux", free=120 * GB)
    if case == "check":
        return dict(disk, case="asleep", why="check", says="")
    if case == "unread":
        return dict(disk, case="asleep", why="other", says="This software has detected that the NTFS volume is already "
                    "opened by another software thus it refuses to progress to preserve data consistency.")
    if case == "small":     # a tablet's 29 GB of eMMC
        return dict(disk, name="/dev/mmcblk0", model="eMMC", size=29 * GB, case="empty", parts=[])
    return dict(disk, case=case)

def plan(d):
    """Next to what is on the disk: in its free room, or for Windows in room made by shrinking it, Windows keeping what it
    uses and room to grow. Tacit needs 64 GB at least; without GPT and an EFI partition there is no "next to"."""
    if d.get("case") not in ("windows", "linux", "other") or not (d.get("gpt") and d.get("esp")):
        return None
    if d.get("free", 0) >= MIN_TACIT:
        return {"windowsKeeps": None, "tacitGets": d["free"], "room": True}
    if d["case"] != "windows" or d.get("used") is None:
        return {"windowsKeeps": None, "tacitGets": d.get("free", 0), "room": False}
    # the free space split evenly, Windows keeping at least 25 GB of it for its updates and files (tacit-install refuses
    # under 20 GB): about 65 GB free is enough. It was a quarter more than Windows used and 47 GB, at least 100 GB, and
    # keeping Windows wanted about 120 GB free (owner 2026-10-17: "120gb to install os ? how")
    keep = min(d["used"] + max(25 * GB, (d["winSize"] - d["used"]) // 2), d["winSize"])
    return {"windowsKeeps": keep, "tacitGets": d["winSize"] - keep, "room": d["winSize"] - keep >= MIN_TACIT}

# The plan each disk was shown with. Install measures the disk again, and a second read could disagree with the one the
# person decided on: it refused "no room next to it" right after showing room (Discord 2026-10-23, Tamrawii)
shown = {}
def show(d):
    shown[d.get("name")] = plan(d)
    return shown[d.get("name")]

def no_room(d, pl):
    """Why "next to" cannot go on this disk, in the words Setup shows after "What stopped it:"."""
    if d.get("case") == "bitlocker":
        return "BitLocker is on for this disk"
    if d.get("case") == "asleep" and d.get("why") == "check":
        return "Windows has a disk check waiting (restart Windows twice, then shut it down)"
    if d.get("case") == "asleep" and d.get("why") == "other":
        return "Setup could not read Windows' partition safely"
    if d.get("case") == "asleep":
        return "Windows is hibernated rather than shut down (turn off Fast Startup in Windows, then shut it down)"
    if not d.get("gpt"):
        return "this disk uses the older MBR layout"
    if not d.get("esp"):
        return "this disk has no EFI partition"
    if d.get("case") == "windows" and d.get("used") is None:
        return "Setup could not read how much of Windows' partition is in use"
    return f"Tacit needs {MIN_TACIT // GB} GB and only {(pl or {}).get('tacitGets', 0) // GB} GB can be made free"

def uefi():
    """The stick was started through UEFI: tacit-install refuses otherwise (it cannot write the start-up entry), and it said
    so only after the disk page and the erase page. A practice run is on whatever this computer is."""
    return not REAL or os.path.isdir("/sys/firmware/efi/efivars")

def no_next(d):
    """Why "next to" is not offered on this disk, for Setup to say under the choice; "" when it is, or not known (a practice
    run cannot read the partition table, and a disk of no known layout is not called MBR)."""
    pl = plan(d)
    if d.get("case") not in ("windows", "linux", "other") or "gpt" not in d or (pl and pl["room"]):
        return ""
    return no_room(d, pl)

def shown_disk(d):
    """The disk as Setup is told of it: with noNext, as the case "nouefi" where nothing can be installed, and as "small"
    under the 32 GB tacit-install refuses (a lone 16 GB disk said "Tacit will use the whole disk", and the refusal came
    only after Install, with a Try again that could not work)."""
    if d.get("case") != "none" and not uefi():
        return dict(d, case="nouefi")
    if d.get("case") not in ("none", "choose") and d.get("size", 0) < MIN_TACIT:
        return dict(d, case="small")
    return dict(d, noNext=no_next(d))

# ------------------------------------------------------------------ power
def power():
    base = "/sys/class/power_supply"
    ac, pct, battery = False, None, False
    def read(n, f):
        try:
            return open(f"{base}/{n}/{f}").read().strip()
        except OSError:
            return ""
    try:
        names = os.listdir(base)
    except OSError:
        names = []
    for n in names:
        t = read(n, "type")
        # a wireless mouse's, keyboard's or controller's own battery (scope Device) is not the computer's: a desktop with
        # one was asked to plug in a charger it does not have. A charger on USB-C is type USB
        if t == "Battery" and read(n, "scope") == "Device":
            continue
        if t in ("Mains", "USB") and read(n, "online") == "1":
            ac = True
        battery = battery or t == "Battery"
        if t == "Battery" and pct is None:
            c = read(n, "capacity")
            if c.isdigit() and int(c) > 0:
                pct = int(c)
    # a computer without a battery (a desktop) is always on the charger: Setup asked it to plug one in
    return {"ac": ac or not battery, "battery": pct}

# ------------------------------------------------------------------ the practice install
install = {"running": False}
starting = threading.Lock()   # one install request at a time decides whether to start

def practice_install():
    install["running"] = True
    t0 = time.time()
    while True:
        f = min(1.0, (time.time() - t0) / SECONDS)
        if FAIL and f >= 0.6:
            emit({"ev": "install", "state": "failed", "done": f, "untouched": True})
            break
        left = SECONDS * (1 - f)
        # no time for the first 15 s: there is nothing to measure yet
        emit({"ev": "install", "state": "done" if f >= 1 else "running", "done": round(f, 3),
              "left": None if time.time() - t0 < 15 else round(left)})
        if f >= 1:
            break
        time.sleep(1)
    install["running"] = False

# ------------------------------------------------------------------ the real install (tacit-install as root)
def real_install(disk, place, keep, manual=None):
    install["running"] = True
    heard = []
    try:
        run_installer(disk, place, keep, manual, heard)
    except Exception:
        # an installer that could not start or be written to (sudo or python3 missing, its pipe closed at once) is still an
        # answer to Setup, or the page says "Installing" for good and a second try is ignored; untouched until it has spoken
        traceback.print_exc(file=open("/tmp/tacit-install.log", "a"))
        emit({"ev": "install", "state": "failed", "done": 0, "untouched": not heard, "reason": ""})
    finally:
        install["running"] = False

def short_reason(reason):
    """A tool's failure, "<tool> failed: <what it said>", as the tool and the last line of what it said, for one line of the page."""
    m = re.match(r"(\S+) failed:(.*)", reason, re.S)
    if not m:
        return reason
    last = next((l.strip() for l in reversed(m.group(2).splitlines()) if l.strip()), "")
    return f"{m.group(1)} failed" + (f": {last[:140]}".rstrip(". ") if last else "")

def run_installer(disk, place, keep, manual, heard):
    t0 = time.time()
    p = subprocess.Popen(["sudo", "-n", "python3", "-I", INSTALLER], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=open("/tmp/tacit-install.log", "w"), text=True)   # what it says on the way, for a failure
    install["proc"] = p
    # the install request cleared the last run's answers and "sent": any answers here are this run's, typed before the
    # installer was there to take them
    try:
        p.stdin.write(json.dumps(dict({"disk": disk, "place": place, "keep": keep}, **(manual or {}))) + "\n")
        p.stdin.flush()
        if install.get("answers"):
            send_answers()
    except OSError:
        pass    # it exited at once (sudo refused, python crashed): no output, so the failure below answers Setup
    ended = False
    for line in p.stdout:
        heard.append(line)
        try:
            m = json.loads(line)
        except ValueError:
            continue
        done = m.get("done", 0)
        # time left from the pace so far, once there is a pace to go by
        left = None if time.time() - t0 < 15 or done <= 0.02 else round((time.time() - t0) * (1 - done) / done)
        ev = {"ev": "install", "state": m["state"], "done": done, "left": left, "other": m.get("other")}
        if m["state"] == "failed":
            # the installer's own reasons are plain words ("the disk is smaller than 32 GB"); a tool's failure ("sgdisk failed:
            # ..." and its last 300 characters) is the tool's name and its last line, which is what a person can say in a
            # report, with all of it in /tmp/tacit-install.log. It was blanked, and "didn't finish" was all the page said
            ev.update(untouched=m.get("untouched", False), reason=short_reason(m.get("reason", "")))
        emit(ev)
        ended = m["state"] in ("done", "failed")
    p.wait()
    if not ended:
        emit({"ev": "install", "state": "failed", "done": 0, "untouched": False, "reason": "the installer stopped"})

def send_answers():
    p = install.get("proc")
    if p and p.poll() is None and not install.get("sent"):
        install["sent"] = True
        p.stdin.write(json.dumps({"answers": install["answers"]}) + "\n")
        p.stdin.flush()

# ------------------------------------------------------------------ requests
# Setup asks "hello" every 0.3 s until it is answered, and the first screen needs only the languages, keyboards and
# Wi-Fi. The disks came in the same answer: reading every disk takes a while on a PC with several big NTFS drives,
# each ask started another full read, they piled up by the hundred, and for minutes Setup showed no languages and said
# there was no disk (Discord 2026-11-01, three game drives). Now hello answers at once, the disks follow in their own
# message ("disks"), and one read runs at a time.
surveying = threading.Lock()
zone_asked = threading.Event()
# the disks as the last read found them, which a disk chosen from the list and the install go by: each read every disk
# again, as root, beside a read that could still be running, so slow NTFS reads hit their 60 s limit and the chosen disk
# could show as unreadable. Only a survey reads them again (Try again, the partition editor closed, a slow drive)
last = {"disks": None}

def installer_left():
    """An installer still running that this helper did not start: one a helper that stopped mid-install had started. It
    goes on as root until its next progress line finds no one to read it, then takes away what it made and stops."""
    if install.get("proc"):
        return False
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                if INSTALLER in f.read().decode(errors="replace").split("\0"):
                    return True
        except OSError:
            pass
    return False

def survey():
    if not surveying.acquire(blocking=False):
        return
    try:
        # Try again starts the helper again after one stopped mid-install: the disks are read once its installer is gone,
        # as they are then, and Install waits for this read
        while installer_left():
            time.sleep(1)
        many = all_disks()          # every disk read once (it was read twice: once for the disk, once for the list)
        last["disks"] = many
        d = disks(many)
        # the disk list only where there is a choice to make
        listed = [dict(x, plan=show(x), noNext=no_next(x)) for x in many] if len(many) > 1 else []
        # every partition on every disk inside, for "Choose partitions myself" (with one disk too)
        parts = [dict(p, disk=x["name"], model=x["model"]) for x in many for p in x.get("parts", [])]
        emit({"ev": "disks", "disks": listed, "disk": shown_disk(d), "plan": show(d), "parts": parts})
    finally:
        surveying.release()

def act(req):
    op = req.get("op")
    if op == "hello":
        if REAL and not zone_asked.is_set():
            zone_asked.set()
            threading.Thread(target=find_zone, daemon=True).start()
        emit({"ev": "hello", "practice": not REAL, "languages": [{"code": c, "name": n, "layout": k, "rtl": c in RTL, "translated": translated(c)} for c, n, k in LANGUAGES],
              "layouts": layouts(), "keyboard": live_keyboard(), "nonLatin": sorted(NON_LATIN), "wifi": wifi(), "wired": wired(), "power": power(), "scenario": SCENARIO})
        survey()
    elif op == "disks":
        # read again: a slow drive that came up after the first read, or a disk a failed install changed
        survey()
    elif op == "wifi":
        emit({"ev": "wifi", "wifi": wifi(), "wired": wired()})
    elif op == "disk":
        if not install["running"]:
            chosen["name"] = req.get("name")
        d = disks(last["disks"])
        emit({"ev": "disk", "disk": shown_disk(d), "plan": show(d)})
    elif op == "power":
        emit({"ev": "power", "power": power()})
    elif op == "join":
        if REAL:
            # NetworkManager joins it (and keeps it, so the installed system has it too); the password stays in argv
            # only for nmcli's own run on this live system
            # nmcli gives up on its own (--wait) before our timeout; a run that still overruns, or cannot start, is a
            # join that did not happen, and Setup is always answered
            cmd = ["nmcli", "--wait", "30", "dev", "wifi", "connect", req.get("ssid", "")] + (["password", req.get("password", "")] if req.get("secure") else [])
            if req.get("hidden"):
                cmd += ["hidden", "yes"]
            why = ""
            try:
                r = subprocess.run(cmd, capture_output=True, text=True, errors="replace", timeout=45)
                ok = r.returncode == 0
                if not ok:
                    why = join_failure(r.stdout + r.stderr)
            except (subprocess.TimeoutExpired, OSError):
                ok, why = False, "network"
        else:
            # practice: nothing is joined. A password under 8 characters is "wrong", so that screen can be seen.
            time.sleep(1.2)
            ok = not req.get("secure") or len(req.get("password", "")) >= 8
            why = "" if ok else "password"
        if ok and REAL and not zone["name"]:
            threading.Thread(target=find_zone, daemon=True).start()
        emit({"ev": "join", "ssid": req.get("ssid"), "ok": ok, "why": why})
    elif op == "install":
        # claimed before the disks are looked at (a read still running is waited for): a second request in that time
        # started a second installer on the same disk
        with starting:
            if install["running"]:
                return
            install["running"] = True
        try:
            # a retry's new installer has had no answers: the person answers again after this request, and only those go
            install.pop("answers", None)
            install["sent"] = False
            if REAL and req.get("place") == "manual":
                # the partitions the person chose: tacit-install checks each one again before it changes anything
                manual = {k: req.get(k) for k in ("root", "efi", "boot")}
                threading.Thread(target=real_install, args=(None, "manual", None, manual), daemon=True).start()
            elif REAL:
                with surveying:     # a read of disks a failed install changed, still running, is the one to go by
                    d = disks(last["disks"])
                pl = plan(d)
                # "next to" is never turned into an erase: without room it stops before anything changes. Room shown
                # earlier goes ahead on the shown plan: tacit-install measures again before it shrinks anything and stops
                # with the disk untouched, in its own words, where there is none
                if req.get("place") == "next" and not (pl and pl["room"]):
                    seen = shown.get(d.get("name"))
                    with open("/tmp/tacit-setup-plan.log", "a") as log:
                        print(json.dumps({"disk": d, "now": pl, "shown": seen}), file=log)
                    if not (seen and seen["room"]):
                        emit({"ev": "install", "state": "failed", "done": 0, "untouched": True, "reason": no_room(d, pl)})
                        install["running"] = False
                        return
                    pl = seen
                place = "next" if req.get("place") == "next" else "instead"
                keep = pl["windowsKeeps"] if place == "next" else None
                threading.Thread(target=real_install, args=(d.get("name"), place, keep), daemon=True).start()
            else:
                threading.Thread(target=practice_install, daemon=True).start()
        except Exception:
            # Setup is always answered: a request that broke before the installer started leaves nothing changed
            install["running"] = False
            emit({"ev": "install", "state": "failed", "done": 0, "untouched": True, "reason": ""})
            raise
    elif op == "editor":
        # the live system's partition editor, for "Choose partitions myself"; when it closes the disks are read again,
        # so what was made there is offered at once
        def edit():
            if REAL and shutil.which("gparted"):
                subprocess.run(["sudo", "-n", "-E", "gparted"], capture_output=True)
            emit({"ev": "editorClosed"})
            survey()
        threading.Thread(target=edit, daemon=True).start()
    elif op == "answers":
        if REAL:
            # a cable that connected after Setup started, or a network that came after "Not now" on Wi-Fi, was never
            # asked: the installed system kept UTC with nothing said. Asked once more here (8 s at most) when none is known
            find_zone()
            install["answers"] = {k: v for k, v in req.items() if k != "op"}
            install["answers"]["timezone"] = zone["name"]
            send_answers()
            # the zone the installed system gets: "" is UTC, which the Ready page says
            emit({"ev": "answers", "ok": True, "zone": zone["name"]})
            return
        # practice: kept for review only, never the password
        a = {k: v for k, v in req.items() if k not in ("op", "password")}
        os.makedirs(os.path.expanduser("~/.cache/tacit-setup"), exist_ok=True)
        with open(os.path.expanduser("~/.cache/tacit-setup/answers.json"), "w") as f:
            json.dump(a, f, indent=1)
        emit({"ev": "answers", "ok": True})
    elif op == "restart":
        restart(req.get("windows") is True)
    elif op == "off":
        if REAL:
            subprocess.run(["sudo", "-n", "systemctl", "poweroff"])

def boot_windows_next():
    """The firmware's BootNext set to Windows's own entry, so the one restart starts Windows even where the firmware prefers
    the USB stick (it started the stick again, and Setup returned to its first page). Best effort: with no entry found, or
    no variables to write, the restart is the plain one."""
    r = as_root("efibootmgr")
    m = re.search(r"^Boot([0-9A-Fa-f]{4})\*?\s+Windows Boot Manager", r.stdout if r else "", re.M)
    if m:
        as_root("efibootmgr", "--bootnext", m.group(1))

def restart(windows=False):
    if REAL:
        if windows:
            boot_windows_next()
        subprocess.run(["sudo", "-n", "systemctl", "reboot"])

def main():
    # os.read, not sys.stdin: a buffered readline() keeps lines select() can no longer see
    fd, buf = sys.stdin.fileno(), b""
    while True:
        r, _, _ = select.select([fd], [], [], 10)
        if not r:
            emit({"ev": "power", "power": power()})
            continue
        chunk = os.read(fd, 65536)
        if not chunk:
            return
        buf += chunk
        *lines, buf = buf.split(b"\n")
        for line in lines:
            try:
                req = json.loads(line)
            except ValueError:
                continue
            threading.Thread(target=act, args=(req,), daemon=True).start()

if __name__ == "__main__":
    main()
