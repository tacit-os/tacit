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


{"small": small, "reuse": reuse, "zone": zone}[sys.argv[2]]()
sys.exit(1 if bad else 0)
