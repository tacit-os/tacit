#!/usr/bin/env python3

# From https://github.com/difference-engine/thumbnail-generator-ubuntu (MIT License)
# Since the script is small and the maintainers seem inactive to accept my PR (#11) I decided to just copy it over.
# When it gets merged and the python package gets updated we can just use it

import os
import sys
from multiprocessing import Pool
from pathlib import Path
from typing import List, Tuple, Union

import click
import gi
from loguru import logger
from tqdm import tqdm

gi.require_version("GnomeDesktop", "4.0")
from gi.repository import Gio, GnomeDesktop  # isort:skip

thumbnail_size_map = {
    "normal": GnomeDesktop.DesktopThumbnailSize.NORMAL,
    "large": GnomeDesktop.DesktopThumbnailSize.LARGE,
    "x-large": GnomeDesktop.DesktopThumbnailSize.XLARGE,
    "xx-large": GnomeDesktop.DesktopThumbnailSize.XXLARGE,
}

factory = None
# The debug sink records one path per file, so it belongs in the user's own state directory
# rather than world-readable /tmp, and it is not kept forever.
log_dir = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state") / "quickshell"
log_dir.mkdir(parents=True, exist_ok=True)
logger.remove()
logger.add(sys.stdout, level="INFO")
logger.add(log_dir / "thumbgen.log", level="DEBUG", rotation="2 MB", retention="3 days")

def init_worker(size: str) -> None:
    # Each worker makes its own factory. A global set in main() reached the workers only through fork: under spawn or
    # forkserver (Python 3.14's default on Linux) a worker imports this file afresh with factory None, and every file
    # failed, said only in the debug log.
    global factory
    factory = GnomeDesktop.DesktopThumbnailFactory.new(thumbnail_size_map[size])


def make_thumbnail(fpath: str) -> Union[bool, None]:
    """True: made; False: not needed (fresh, or a kind it cannot thumbnail); None: it failed"""
    # one file that cannot be read (deleted during the run, a corrupt picture) must not stop the rest of the folder
    try:
        mtime = os.path.getmtime(fpath)
        # Use Gio to determine the URI and mime type
        f = Gio.file_new_for_path(str(fpath))
        uri = f.get_uri()
        info = f.query_info("standard::content-type", Gio.FileQueryInfoFlags.NONE, None)
        mime_type = info.get_content_type()

        if factory.lookup(uri, mtime) is not None:
            logger.debug("FRESH       {}".format(uri))
            return False

        if not factory.can_thumbnail(uri, mime_type, mtime):
            logger.debug("UNSUPPORTED {}".format(uri))
            return False

        thumbnail = factory.generate_thumbnail(uri, mime_type)
        if thumbnail is None:
            logger.debug("ERROR       {}".format(uri))
            return None

        logger.debug("OK          {}".format(uri))
        factory.save_thumbnail(thumbnail, uri, mtime)
        return True
    except Exception as e:
        logger.debug("ERROR       {} ({})".format(fpath, e))
        return None


# reraise: a folder that is missing, or one where every file failed, must end the run with a failure, so the caller's
# magick fallback runs
@logger.catch(reraise=True)
def thumbnail_folder(*, dir_path: Path, size: str, workers: int, only_images: bool, recursive: bool, machine_progress: bool = False) -> None:
    all_files = get_all_files(dir_path=dir_path, recursive=recursive)
    if only_images:
        all_files = get_all_images(all_files=all_files)
    all_files = [str(fpath) for fpath in all_files]
    results = []
    if machine_progress:
        completed = 0
        total = len(all_files)
        with Pool(processes=workers, initializer=init_worker, initargs=(size,)) as p:
            for result in p.imap(make_thumbnail, all_files):
                results.append(result)
                completed += 1
                print(f"PROGRESS {completed}/{total} FILE {all_files[completed-1]}")
                sys.stdout.flush()
    else:
        with Pool(processes=workers, initializer=init_worker, initargs=(size,)) as p:
            results = list(tqdm(p.imap(make_thumbnail, all_files), total=len(all_files)))
    if results and all(r is None for r in results):
        raise RuntimeError("no thumbnail could be made in {}".format(dir_path))


def get_all_images(*, all_files: List[Path]) -> List[Path]:
    img_suffixes = [".jpg", ".jpeg", ".png", ".gif"]
    all_images = [fpath for fpath in all_files if fpath.suffix in img_suffixes]
    print("Found {} images".format(len(all_images)))
    return all_images


def get_all_files(*, dir_path: Path, recursive: bool) -> List[Path]:
    if not (dir_path.exists() and dir_path.is_dir()):
        raise ValueError("{} doesn't exist or isn't a valid directory!".format(dir_path.resolve()))
    if recursive:
        all_files = dir_path.rglob("*")
    else:
        all_files = dir_path.glob("*")
    all_files = [fpath for fpath in all_files if fpath.is_file()]
    print("Found {} files in the directory: {}".format(len(all_files), dir_path.resolve()))
    return all_files

@click.command()
@click.option(
    "-d", "--img_dirs", required=True, multiple=True, help="a directory to generate thumbnails for; give -d once per directory"
)
@click.option(
    "-s", "--size", default="normal", type=click.Choice(["normal", "large", "x-large", "xx-large"]), help="Thumbnail size: normal, large, x-large, xx-large"
)
@click.option("-w", "--workers", default=1, help="no of cpus to use for processing")
@click.option(
    "-i", "--only_images", is_flag=True, default=False, help="Whether to only look for images to be thumbnailed"
)
@click.option("-r", "--recursive", is_flag=True, default=False, help="Whether to recursively look for files")
@click.option("--machine_progress", is_flag=True, default=False, help="Print machine-readable progress lines instead of a progress bar")
def main(img_dirs: Tuple[str, ...], size: str, workers: str, only_images: bool, recursive: bool, machine_progress: bool) -> None:
    img_dirs = [Path(img_dir) for img_dir in img_dirs]
    for img_dir in img_dirs:
        thumbnail_folder(dir_path=img_dir, size=size, workers=workers, only_images=only_images, recursive=recursive, machine_progress=machine_progress)
    print("Thumbnail Generation Completed!")


if __name__ == "__main__":
    main()
