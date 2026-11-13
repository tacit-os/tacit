"""setupd.py's answers to Setup on made-up disks: python3 setupd_cases.py <setupd.py> <case>. Loads Setup's helper as a
module with its disk reads replaced by the disks each check names (nothing is read as root, nothing is written) and
checks what it sends Setup."""
import importlib.util, os, sys
GB = 10 ** 9
bad = 0


def load():
    os.environ.pop("TACIT_SETUP_SCENARIO", None)
    spec = importlib.util.spec_from_file_location("setupd", sys.argv[1])
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.sent = []
    m.emit = m.sent.append
    return m


def disk(name, size, case, **kw):
    return dict({"name": name, "model": "Disk", "size": size, "case": case, "parts": []}, **kw)


def check(name, ok, got=""):
    global bad
    bad += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}" + ("" if ok or not got else f": {got}"))


def small():
    """A disk under the 32 GB tacit-install refuses is the case "small", alone or chosen from the list."""
    windows = disk("/dev/nvme0n1", 1000 * GB, "windows", gpt=True, esp=True, free=0, used=140 * GB, winSize=998 * GB)
    emmc = disk("/dev/mmcblk0", 29 * GB, "empty")
    for name, ds, want in [
        ("a tablet's 29 GB of eMMC, alone: too small", [emmc], "small"),
        ("a 16 GB disk with Linux on it: too small", [disk("/dev/sda", 16 * GB, "linux", gpt=True, esp=True, free=0)], "small"),
        ("an empty disk of exactly 32 GB, which tacit-install takes: the whole disk", [disk("/dev/sda", 32 * GB, "empty")], "empty"),
        ("an empty 512 GB disk: the whole disk", [disk("/dev/sda", 512 * GB, "empty")], "empty"),
        ("no disk inside", [], "none"),
        ("Windows on 1 TB beside the 29 GB eMMC: the person chooses", [windows, emmc], "choose"),
    ]:
        m = load()
        m.all_disks = lambda ds=ds: ds
        m.survey()
        got = m.sent[-1]["disk"]["case"]
        check(name, got == want, f"case {got}")
    m = load()
    m.all_disks = lambda: [windows, emmc]
    m.survey()
    m.act({"op": "disk", "name": "/dev/mmcblk0"})
    check("the 29 GB eMMC chosen from the list: too small", m.sent[-1]["disk"]["case"] == "small", f"case {m.sent[-1]['disk']['case']}")
    m.act({"op": "disk", "name": "/dev/nvme0n1"})
    check("Windows chosen from the list after it: Windows", m.sent[-1]["disk"]["case"] == "windows", f"case {m.sent[-1]['disk']['case']}")


def reuse():
    """Choosing a disk and Install go by the disks as the survey read them: each read every disk again, as root, beside
    a survey that could still be running. A survey still running when Install comes is waited for."""
    import threading, time
    before = disk("/dev/nvme0n1", 512 * GB, "windows", gpt=True, esp=True, free=0, used=140 * GB, winSize=510 * GB)
    games = disk("/dev/sda", 2000 * GB, "other", gpt=True, esp=False, free=0)
    m = load()
    m.REAL = True
    m.uefi = lambda: True
    reads, started = [], []
    m.all_disks = lambda: reads.append(1) or [before, games]
    m.real_install = lambda *a: started.append(a)
    m.survey()
    m.act({"op": "disk", "name": "/dev/nvme0n1"})
    answer = m.sent[-1]
    check("choosing a disk reads no disk again", len(reads) == 1, f"{len(reads)} reads of every disk")
    check("and answers with the disk as the survey read it", answer["disk"]["case"] == "windows" and answer["plan"]["room"], str(answer))
    m.act({"op": "install", "place": "next"})
    for _ in range(50):
        if started:
            break
        time.sleep(0.02)
    check("Install reads no disk again", len(reads) == 1, f"{len(reads)} reads of every disk")
    check("and installs next to Windows on the plan shown", started == [("/dev/nvme0n1", "next", answer["plan"]["windowsKeeps"])], str(started))

    # Try again after a failed install: the disks are being read again when Install comes
    m.install["running"] = False
    started.clear()
    after = dict(before, free=185 * GB, used=140 * GB, winSize=325 * GB)
    go = threading.Event()
    m.all_disks = lambda: go.wait(5) and [after, games]
    survey = threading.Thread(target=m.survey)
    survey.start()
    time.sleep(0.1)
    install = threading.Thread(target=m.act, args=({"op": "install", "place": "next"},))
    install.start()
    time.sleep(0.3)
    waited = not started
    go.set()
    survey.join(5)
    install.join(5)
    check("Install while the disks are read again waits for that read", waited, f"started {started} first")
    check("and goes by what it read (the free room, no second shrink)", started == [("/dev/nvme0n1", "next", None)], str(started))


def zone():
    """The time zone handed to tacit-install: looked up again as the answers go when the first lookup found none, and
    told to Setup with the answer ("" for none: the Ready page says the clock is on UTC)."""
    import time
    answers = {"op": "answers", "name": "Sam", "password": "pw", "language": "sv_SE", "layout": "se"}
    for name, online_at, want, asks in [
        ("a cable that connects after Setup started: the zone is looked up again with the answers", "answers", "Europe/Stockholm", 2),
        ("online from the start: found at the first hello and not looked up again", "hello", "Europe/Stockholm", 1),
        ("never online: the answers still go, with no zone (UTC)", None, "", None),
    ]:
        m = load()
        m.REAL = True
        online, asked = [online_at == "hello"], []
        def run(*cmd, timeout=10, online=online, asked=asked):
            if cmd[0] != "curl":
                return ""
            asked.append(1)
            return "<Response><TimeZone>Europe/Stockholm</TimeZone></Response>" if online[0] else ""
        m.run = run
        m.as_root = lambda *cmd: None
        m.wifi, m.wired, m.layouts, m.live_keyboard, m.survey = (lambda: []), (lambda: False), (lambda: []), (lambda: "us"), (lambda: None)
        m.act({"op": "hello"})
        time.sleep(0.2)     # the first lookup, on its own thread
        online[0] = online_at in ("hello", "answers")
        m.act(answers)
        got = m.install.get("answers", {}).get("timezone")
        check(name, got == want and asks in (None, len(asked)) and m.sent[-1] == {"ev": "answers", "ok": True, "zone": want},
              f"timezone {got!r}, {len(asked)} lookups, last sent {m.sent[-1]}")


def enterprise():
    """An 802.1X network, as nmcli names it in SECURITY, is told apart from one a password alone joins."""
    m = load()
    m.run = lambda *cmd, timeout=10: "*:Home:80:WPA2\n :eduroam:70:WPA2 802.1X\n :Office\\:3F:60:WPA1 WPA2 802.1X\n" \
        " :Flat:50:WPA3\n :Cafe:40:\n" if cmd[:1] == ("nmcli",) else ""
    nets = {n["ssid"]: n for n in m.wifi()}
    for ssid, want in [("eduroam", True), ("Office:3F", True), ("Home", False), ("Flat", False), ("Cafe", False)]:
        got = nets.get(ssid, {}).get("enterprise")
        check(f"{ssid}: {'802.1X' if want else 'not 802.1X'}", got is want, f"enterprise {got!r}")
    check("an 802.1X network still shows as locked", nets["eduroam"]["secure"] is True)


def power():
    """On the charger or not, from a made-up /sys/class/power_supply: a mouse's, keyboard's or controller's battery is
    not the computer's, and a charger on USB-C is a charger."""
    import tempfile, types
    sysfs = "/sys/class/power_supply"
    mouse = {"type": "Battery", "scope": "Device", "capacity": "90"}
    pad = {"type": "Battery", "scope": "Device", "capacity": "60", "online": "1"}
    bat = {"type": "Battery", "capacity": "40"}
    for name, supplies, want in [
        ("a desktop with a wireless mouse: on mains", {"hidpp_battery_0": mouse}, {"ac": True, "battery": None}),
        ("a desktop with a controller and a Bluetooth keyboard: on mains",
         {"ps-controller-battery-aa:bb": pad, "hid-cc:dd-battery": mouse}, {"ac": True, "battery": None}),
        ("a desktop with nothing: on mains", {}, {"ac": True, "battery": None}),
        ("a laptop on its battery", {"BAT0": bat, "AC": {"type": "Mains", "online": "0"}}, {"ac": False, "battery": 40}),
        ("a laptop on its battery, with a mouse: its own battery's 40 %",
         {"BAT0": bat, "AC": {"type": "Mains", "online": "0"}, "hidpp_battery_0": mouse}, {"ac": False, "battery": 40}),
        ("a laptop on its charger", {"BAT0": bat, "AC": {"type": "Mains", "online": "1"}}, {"ac": True, "battery": 40}),
        ("a laptop charged by USB-C only, on it", {"BAT1": bat, "ucsi-source-psy-USBC000:001": {"type": "USB", "online": "1"}},
         {"ac": True, "battery": 40}),
        ("a laptop with USB-C charging, on its battery", {"BAT1": bat, "ucsi-source-psy-USBC000:001": {"type": "USB", "online": "0"}},
         {"ac": False, "battery": 40}),
    ]:
        with tempfile.TemporaryDirectory() as base:
            for n, files in supplies.items():
                os.makedirs(f"{base}/{n}")
                for f, v in files.items():
                    with open(f"{base}/{n}/{f}", "w") as fh:
                        fh.write(v + "\n")
            m = load()
            # the helper's reads of /sys/class/power_supply go to the made-up one
            m.open = lambda p, *a, base=base, **k: open(p.replace(sysfs, base, 1), *a, **k)
            m.os = types.SimpleNamespace(**dict(vars(os), listdir=lambda p, base=base: os.listdir(p.replace(sysfs, base, 1))))
            got = m.power()
        check(name, got == want, str(got))


def left():
    """After a helper stopped mid-install, its installer goes on as root until its next progress line finds no one to
    read it: the helper started again by Try again reads the disks once that installer has gone, and Install waits for
    that read. A stand-in with the installer's path in its command line plays the installer (nothing is installed)."""
    import subprocess, threading, time
    m = load()
    m.REAL = True
    m.uefi = lambda: True
    w = disk("/dev/nvme0n1", 512 * GB, "windows", gpt=True, esp=True, free=0, used=140 * GB, winSize=510 * GB)
    stand_in = subprocess.Popen([sys.executable, "-I", "-c", "import time; time.sleep(1.5)", m.INSTALLER])
    reads, started = [], []
    m.all_disks = lambda: reads.append(stand_in.poll() is not None) or [w]
    m.real_install = lambda *a: started.append(stand_in.poll() is not None)
    survey = threading.Thread(target=m.survey)
    survey.start()
    time.sleep(0.2)
    install = threading.Thread(target=m.act, args=({"op": "install", "place": "instead"},))
    install.start()
    survey.join(10)
    install.join(10)
    stand_in.wait()
    check("the disks are read only once the installer left behind has gone", reads == [True], f"reads with it gone: {reads}")
    check("and Install, asked meanwhile, starts only after that", started == [True], f"installs with it gone: {started}")
    check("the page is answered", m.sent and m.sent[0].get("ev") == "disks", str(m.sent[:1]))

    # this helper's own installer is no reason to wait: the read after its own failed install goes ahead
    m = load()
    m.install["proc"] = object()
    stand_in = subprocess.Popen([sys.executable, "-I", "-c", "import time; time.sleep(1.5)", m.INSTALLER])
    reads = []
    m.all_disks = lambda: reads.append(stand_in.poll() is None) or [w]
    m.survey()
    stand_in.kill()
    stand_in.wait()
    check("a helper's own installer does not hold up its read", reads == [True], f"reads with it running: {reads}")


{"small": small, "reuse": reuse, "zone": zone, "enterprise": enterprise, "power": power, "left": left}[sys.argv[2]]()
sys.exit(1 if bad else 0)
