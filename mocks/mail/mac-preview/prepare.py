#!/usr/bin/env python3
"""Stage the sibling Tacit Kit with the Mac preview's local palette transport."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


PREVIEW = Path(__file__).resolve().parent
KIT = Path(os.environ.get("TACIT_KIT_DIR", PREVIEW.parents[3] / "tacit-kit")).resolve()


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one occurrence of {old!r} in Tacit Kit")
    return text.replace(old, new, 1)


def stage(import_dir):
    source = KIT / "qml" / "Tacit" / "Kit"
    if not (source / "qmldir").is_file():
        raise ValueError(f"Tacit Kit missing at {KIT}. Set TACIT_KIT_DIR to its checkout.")
    target = import_dir / "Tacit" / "Kit"
    shutil.copytree(source, target, dirs_exist_ok=True)

    kit = (source / "Kit.qml").read_text()
    kit = replace_once(kit, "import Quickshell\n", "")
    kit = replace_once(kit, "Singleton {", "Item {")
    kit = replace_once(kit, 'Quickshell.env("TACIT_REDUCED_MOTION") === "1"', "false")
    (target / "Kit.qml").write_text(kit)

    live = (source / "Live.qml").read_text()
    start = live.index("    // the shell's colour maths")
    live = """// SPDX-License-Identifier: LGPL-3.0-or-later
import QtQuick

QtObject {
    id: live
    property var pal: typeof previewPalette === "undefined" ? ({}) : previewPalette
    property real seeThroughScale: typeof previewScale === "undefined" ? 1 : previewScale
    property var transparency: ({ enable: true, automatic: true, backgroundTransparency: 0.15 })
    readonly property bool ready: live.pal.surface_container_low !== undefined

""" + live[start:]
    (target / "Live.qml").write_text(live)

    # Qt Quick takes whole pixel sizes. Scale only typography in the Mac copy.
    for name in ("Defaults.qml", "Live.qml"):
        tokens = target / name
        text = tokens.read_text()
        start = text.index("readonly property QtObject size: QtObject {")
        end = text.index("}", start)
        sizes = re.sub(
            r"(readonly property int \w+: )(\d+)",
            lambda match: match[1] + str((9 * int(match[2]) + 5) // 10),
            text[start:end],
        )
        tokens.write_text(text[:start] + sizes + text[end:])

    subprocess.run(
        ["patch", "-f", "-s", "-p1", "-i", str(PREVIEW.parent / "kit-style/reference.patch")],
        cwd=target,
        check=True,
    )
    for name in ("dusk.json", "moss.json"):
        shutil.copyfile(KIT / "tools" / "palettes" / name, import_dir / name)


if __name__ == "__main__":
    try:
        stage(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else PREVIEW / "build-local/qml")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"Cannot prepare Tacit Mail preview: {error}")
