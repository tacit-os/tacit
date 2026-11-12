"""The greeter's keyboard from tacit-login-ground's own main(), on a throwaway root: python3 -I -B login_ground.py
<tacit-login-ground> <vconsole.conf text> <the person's config.json text, or "">. One person (this user) with a lock
ground and that config.json; a pretend xkb symbols folder with us, de (nodeadkeys), fr and ru. Prints weston.ini."""
import importlib.machinery, importlib.util, os, pwd, shutil, sys, tempfile
sys.dont_write_bytecode = True
script, vconsole, config = sys.argv[1:4]
root = tempfile.mkdtemp(prefix="tacit-login-")
try:
    xkb = os.path.join(root, "xkb"); os.makedirs(xkb)
    for name, body in {"us": 'xkb_symbols "basic" {};', "de": 'xkb_symbols "basic" {};\nxkb_symbols "nodeadkeys" {};',
                       "fr": 'xkb_symbols "basic" {};', "ru": 'xkb_symbols "basic" {};'}.items():
        open(os.path.join(xkb, name), "w").write(body)
    home = os.path.join(root, "home")
    os.makedirs(os.path.join(home, ".local/state/tacit-boot")); os.makedirs(os.path.join(home, ".config/illogical-impulse"))
    open(os.path.join(home, ".local/state/tacit-boot/lock-ground.png"), "wb").write(b"\x89PNG")
    if config:
        open(os.path.join(home, ".config/illogical-impulse/config.json"), "w").write(config)
    open(os.path.join(root, "vconsole.conf"), "w").write(vconsole)
    loader = importlib.machinery.SourceFileLoader("login_ground", script)
    m = importlib.util.module_from_spec(importlib.util.spec_from_loader("login_ground", loader)); loader.exec_module(m)
    m.OUT, m.VCONSOLE, m.XKB, m.WESTON_INI = os.path.join(root, "out"), os.path.join(root, "vconsole.conf"), xkb, os.path.join(root, "weston.ini")
    me = pwd.getpwuid(os.getuid())
    m.pwd.getpwall = lambda: [pwd.struct_passwd((me.pw_name, "x", 1000 if me.pw_uid < 1000 else me.pw_uid, me.pw_gid, "", home, "/bin/sh"))]
    if me.pw_uid < 1000:     # run as root or a system user: the person's files must be owned by the uid it is given
        for d, _, fs in os.walk(home):
            for f in [d, *[os.path.join(d, f) for f in fs]]: os.chown(f, 1000, -1)
    m.main()
    print(open(m.WESTON_INI).read() if os.path.exists(m.WESTON_INI) else "")
finally:
    shutil.rmtree(root)
