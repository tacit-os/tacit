"""tacit-install's choice of NVIDIA's driver on fake PCI devices: python3 nvidia_driver.py <tacit-install>.
Loads the installer's own nvidia_present() (no disk is touched) and checks each computer: True keeps nvidia-open and
nvidia-utils, False removes them and leaves the card to nouveau."""
import glob, os, sys, tempfile, types
src = open(sys.argv[1]).read()
code = src[src.index("def nvidia_present():"):]
code = code[:code.index("\ndef ")]
# (vendor, device, class) as sysfs has them
cases = [
    ("a GeForce GTX 1060 alone (Pascal): nouveau's", False, [("0x10de", "0x1c03", "0x030000"), ("0x10de", "0x10f1", "0x040300")]),
    ("a GeForce GTX 970 alone (Maxwell): nouveau's", False, [("0x10de", "0x13c2", "0x030000")]),
    ("a Tesla V100S (Volta, the last before Turing): nouveau's", False, [("0x10de", "0x1df6", "0x030200")]),
    ("a TITAN RTX (Turing, the first NVIDIA's open driver takes)", True, [("0x10de", "0x1e02", "0x030000")]),
    ("an RTX 4050 laptop beside Intel graphics", True, [("0x8086", "0xa7a0", "0x030000"), ("0x10de", "0x28a1", "0x030200")]),
    ("a GTX 1050 laptop beside Intel graphics: nouveau's", False, [("0x8086", "0x3e9b", "0x030000"), ("0x10de", "0x1c8d", "0x030200")]),
    ("AMD graphics and a Turing card's USB part only", False, [("0x1002", "0x73df", "0x030000"), ("0x10de", "0x1ad6", "0x0c0330")]),
    ("no NVIDIA at all", False, [("0x8086", "0xa7a0", "0x030000")]),
]
bad = 0
for name, want, devs in cases:
    d = tempfile.mkdtemp()
    for i, (vendor, device, cls) in enumerate(devs):
        p = f"{d}/0000:0{i}:00.0"
        os.makedirs(p)
        for k, v in (("vendor", vendor), ("device", device), ("class", cls)):
            open(f"{p}/{k}", "w").write(v + "\n")
    fake = types.SimpleNamespace(glob=lambda pattern, d=d: glob.glob(pattern.replace("/sys/bus/pci/devices", d)))
    ns = {"glob": fake}
    exec(compile(code, "tacit-install", "exec"), ns)
    got = ns["nvidia_present"]()
    ok = got == want
    bad += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: {'keeps' if got else 'removes'} NVIDIA's driver" + ("" if ok else f" (should {'keep' if want else 'remove'} it)"))
print(f"{len(cases) - bad} of {len(cases)} as they should be")
sys.exit(1 if bad else 0)
