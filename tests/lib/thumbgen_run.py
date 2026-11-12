"""thumbgen.py's own main() on a folder of three pictures, with its workers started the way Python 3.14 starts them on
Linux (forkserver), whatever this python's default: python3 -I -B thumbgen_run.py <scripts/thumbnails> ok|fail.
gi, click, loguru and tqdm are stand-ins: GnomeDesktop's factory writes a file for each thumbnail it saves (or, for
"fail", can make none). Prints {"made": [...], "failed": bool}."""
import json, multiprocessing, os, shutil, sys, tempfile


def stubs(d):
    def put(path, text):
        os.makedirs(os.path.dirname(os.path.join(d, path)), exist_ok=True)
        open(os.path.join(d, path), "w").write(text)
    put("click/__init__.py", "def command(*a, **k): return lambda f: f\ndef option(*a, **k): return lambda f: f\ndef Choice(*a, **k): return None\n")
    put("tqdm/__init__.py", "def tqdm(it, **k): return it\n")
    put("loguru/__init__.py", "class _L:\n    def remove(self, *a): pass\n    def add(self, *a, **k): pass\n    def debug(self, *a): pass\n"
        "    def catch(self, **k): return lambda f: f\nlogger = _L()\n")
    put("gi/__init__.py", "def require_version(*a): pass\n")
    put("gi/repository/__init__.py", """import os
class _File:
    def __init__(self, p): self.p = p
    def get_uri(self): return "file://" + self.p
    def query_info(self, *a): return type("I", (), {"get_content_type": lambda s: "image/png"})()
class Gio:
    FileQueryInfoFlags = type("F", (), {"NONE": 0})
    @staticmethod
    def file_new_for_path(p): return _File(p)
class _Factory:
    def lookup(self, uri, mtime): return None
    def can_thumbnail(self, uri, mime, mtime): return True
    def generate_thumbnail(self, uri, mime): return None if os.environ["THUMB_FAIL"] else "pixels"
    def save_thumbnail(self, t, uri, mtime): open(os.path.join(os.environ["THUMB_OUT"], os.path.basename(uri)), "w").close()
class GnomeDesktop:
    DesktopThumbnailSize = type("S", (), {"NORMAL": 0, "LARGE": 1, "XLARGE": 2, "XXLARGE": 3})
    DesktopThumbnailFactory = type("T", (), {"new": staticmethod(lambda size: _Factory())})
""")


if __name__ == "__main__":
    here, mode = sys.argv[1], sys.argv[2]
    work = tempfile.mkdtemp(prefix="tacit-thumbgen-")
    pics, out = os.path.join(work, "pics"), os.path.join(work, "out")
    os.makedirs(pics); os.makedirs(out); stubs(os.path.join(work, "stubs"))
    for n in ("a.png", "b.png", "c.png"):
        open(os.path.join(pics, n), "w").write("x")
    os.environ.update(XDG_STATE_HOME=os.path.join(work, "state"), THUMB_OUT=out, THUMB_FAIL="1" if mode == "fail" else "")
    sys.path[:0] = [os.path.join(work, "stubs"), here]
    multiprocessing.set_start_method("forkserver")
    import thumbgen
    try:
        thumbgen.main(img_dirs=(pics,), size="normal", workers=2, only_images=False, recursive=False, machine_progress=True)
        failed = False
    except Exception:
        failed = True
    print(json.dumps({"made": sorted(os.listdir(out)), "failed": failed}))
    shutil.rmtree(work)
