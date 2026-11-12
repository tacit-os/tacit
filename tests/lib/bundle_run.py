"""What tacit-bundle run starts an app with: python3 -I bundle_run.py <bundle.py> <app> <manifest permissions as JSON>.
A home of its own holds an installed bundle whose manifest says what the app could reach when it was got; the script's
own run() then builds the sandbox, and its bwrap command is printed as JSON instead of started."""
import json, os, sys, tempfile, time
sys.dont_write_bytecode = True   # nothing left beside bundle.py in the tree
bundle_py, app, perms = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
home = tempfile.mkdtemp(prefix="tacit-bundle-")
os.environ.update(HOME=home, XDG_RUNTIME_DIR=os.path.join(home, "run"), WAYLAND_DISPLAY="wayland-1")
os.environ.pop("DBUS_SESSION_BUS_ADDRESS", None); os.environ.pop("DISPLAY", None)
import importlib.util
spec = importlib.util.spec_from_file_location("bundle", bundle_py)
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
base = os.path.join(b.ROOT, app); os.makedirs(os.path.join(base, "root/usr/bin"))
json.dump(dict(package=app, version="1", versions={app: "1"}, shared=[], host_versions={}, host_stamp=b.host_stamp(),
               ids=[], exec=[f"/usr/bin/{app}"], made=[], size=0, installed=int(time.time()), permissions=perms),
          open(os.path.join(base, "manifest.json"), "w"))
b.user_dirs = lambda: [os.path.join(home, "Documents")]
def started(path, argv):
    print(json.dumps({"home": home, "argv": argv})); sys.exit(0)
b.os.execvp = started
b.run(app, [])
