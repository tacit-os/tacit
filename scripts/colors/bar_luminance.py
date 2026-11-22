#!/usr/bin/env python3
"""bar_luminance.py <image>: estimated background lightness behind the top bar, split into left/center/right
thirds. Writes generated/bar_luminance.json as {"left": l, "center": c, "right": r} where each value is CIE
L* (0 dark .. 100 light), sampled from the top strip of the wallpaper after a light blur.

Used when bar.showBackground is off so bar widgets can pick readable ink per zone."""
import json, os, sys
from PIL import Image, ImageFilter

STATE = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
GENERATED = os.path.join(STATE, "quickshell/user/generated")


def linear(v):
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def lightness(c):
    y = 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2])
    return 116 * y ** (1 / 3) - 16 if y > 0.008856 else 903.3 * y


def zone_luminance(image):
    im = Image.open(image).convert("RGB").resize((192, 108)).filter(ImageFilter.GaussianBlur(3))
    w, h = im.size
    # top bar sits at the top edge; sample the top band
    band_h = max(1, h // 6)
    band = im.crop((0, 0, w, band_h))
    px = list(band.getdata())
    bw, bh = band.size
    zones = {}
    for name, x0, x1 in (("left", 0, bw // 3), ("center", bw // 3, 2 * bw // 3), ("right", 2 * bw // 3, bw)):
        vals = []
        for y in range(bh):
            row = y * bw
            for x in range(x0, x1):
                vals.append(lightness(px[row + x]))
        vals.sort()
        # use a bright-ish percentile so highlights behind the bar drive contrast
        zones[name] = round(vals[int(len(vals) * 0.75)], 2)
    return zones


def main():
    image = sys.argv[1]
    try:
        zones = zone_luminance(image)
    except (OSError, ValueError, IndexError) as e:
        print(f"bar_luminance: {e}; defaulting to dark zones", file=sys.stderr)
        zones = {"left": 0.0, "center": 0.0, "right": 0.0}
    os.makedirs(GENERATED, exist_ok=True)
    tmp = os.path.join(GENERATED, "bar_luminance.json.tmp")
    with open(tmp, "w") as f:
        json.dump(zones, f)
    os.replace(tmp, os.path.join(GENERATED, "bar_luminance.json"))
    print(json.dumps(zones))


if __name__ == "__main__":
    main()
