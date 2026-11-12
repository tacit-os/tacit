"""The shared-EFI decision of tacit-install on fake EFI partitions: python3 efi_share.py <tacit-install>.
Loads the installer's own functions (no disk is touched) and checks each case."""
import os, sys, glob, re, tempfile, types
src = open(sys.argv[1]).read()
mod = types.ModuleType("ti"); mod.__dict__.update(os=os, glob=glob, re=re, subprocess=None)
if True:
    if "TACIT_START_FILES" not in src:
        print("FAIL tacit-install has no shared-EFI rule of its own: every initramfs-linux* is taken (1.2.14)"); sys.exit(1)
    code = src[src.index("TACIT_START_FILES = "):src.index("def efi_room(")]
    exec(compile(code.replace("def root_ids", "def _unused_root_ids"), "tacit-install", "exec"), mod.__dict__)
    decide = mod.start_files_taken
ROOT = {"/dev/nvme0n1p2", "uuid=1111-root", "partuuid=aaaa-root"}
def esp(files, entries):
    d = tempfile.mkdtemp()
    for f in files: open(os.path.join(d, f), "w").close()
    os.makedirs(f"{d}/loader/entries", exist_ok=True)
    for name, body in entries.items(): open(f"{d}/loader/entries/{name}", "w").write(body)
    return d
cases = [
    ("CachyOS being replaced (its own kernel names)", False,
     esp(["vmlinuz-linux-cachyos", "initramfs-linux-cachyos.img"],
         {"linux-cachyos.conf": "title CachyOS\nlinux /vmlinuz-linux-cachyos\ninitrd /initramfs-linux-cachyos.img\noptions root=UUID=1111-ROOT rw rootflags=subvol=/@\n"})),
    ("CachyOS on another partition, kept", False,
     esp(["vmlinuz-linux-cachyos", "initramfs-linux-cachyos.img"],
         {"linux-cachyos.conf": "linux /vmlinuz-linux-cachyos\ninitrd /initramfs-linux-cachyos.img\noptions root=UUID=2222-other rw\n"})),
    ("Arch with the same names, on the partition being replaced", False,
     esp(["vmlinuz-linux", "initramfs-linux.img", "initramfs-linux-fallback.img"],
         {"arch.conf": "linux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions root=PARTUUID=aaaa-root rw\n",
          "arch-fallback.conf": "linux /vmlinuz-linux\ninitrd /initramfs-linux-fallback.img\noptions root=PARTUUID=aaaa-root rw\n"})),
    ("an earlier Tacit on the same partition (a reinstall)", False,
     esp(["vmlinuz-linux", "initramfs-linux.img"],
         {"tacit.conf": "title Tacit\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions root=PARTUUID=AAAA-ROOT rw quiet\n"})),
    ("Arch with the same names on ANOTHER partition (kept): refused", True,
     esp(["vmlinuz-linux", "initramfs-linux.img"],
         {"arch.conf": "linux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions root=UUID=2222-other rw\n"})),
    ("Tacit's names with no systemd-boot entry (GRUB's?): refused", True,
     esp(["vmlinuz-linux", "initramfs-linux.img"], {})),
    ("an entry with no root=: refused", True,
     esp(["vmlinuz-linux", "initramfs-linux.img"], {"arch.conf": "linux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions rw\n"})),
    ("an empty EFI partition", False, esp([], {})),
]
bad = 0
for name, want, d in cases:
    got = decide(d, ROOT)
    ok = got == want
    bad += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: {'refused' if got else 'allowed'}" + ("" if ok else f" (should be {'refused' if want else 'allowed'})"))
print(f"{len(cases) - bad} of {len(cases)} as they should be")
sys.exit(1 if bad else 0)
