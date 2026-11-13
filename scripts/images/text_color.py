#!/usr/bin/env python3
# Disclaimer: This script was ai-generated and went through minimal revision.
# text_color.py <image> <x>,<y>,<w>,<h>...: the background and text colour of each box of the image, as one JSON list in
# the boxes' order. One run reads every box of a capture: the screen translator ran one per paragraph, all at once, and
# each loaded OpenCV.

import cv2
import numpy as np
import json
import sys

def to_hex(color):
    return "#{:02x}{:02x}{:02x}".format(int(color[0]), int(color[1]), int(color[2]))

def get_color(img_rgb):
    h, w, _ = img_rgb.shape

    # 1. Sample corner pixels (The background anchors)
    corners = np.array([
        img_rgb[0, 0],
        img_rgb[0, w-1],
        img_rgb[h-1, 0],
        img_rgb[h-1, w-1]
    ])

    # 2. Determine single dominant background
    # Using median handles noise/gradients better than a simple average
    bg_color = np.median(corners, axis=0).astype(int)

    # 3. Find the Text Color
    pixels = img_rgb.reshape(-1, 3).astype(int)
    distances = np.linalg.norm(pixels - bg_color, axis=1)
    
    # Take the 95th percentile of pixels furthest from background
    threshold = np.percentile(distances, 95)
    text_pixels = pixels[distances >= threshold]
    
    if len(text_pixels) == 0:
        text_color = [255, 255, 255] # Fallback
    else:
        text_color = np.median(text_pixels, axis=0).astype(int)

    return {
        "background": to_hex(bg_color),
        "text": to_hex(text_color)
    }

def get_colors(path, boxes):
    img = cv2.imread(path, cv2.IMREAD_COLOR)
    if img is None:
        return [{"error": "Could not read the image"} for _ in boxes]
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    results = []
    for box in boxes:
        try:
            x, y, w, h = (int(float(v)) for v in box.split(","))
        except ValueError:
            results.append({"error": f"Not a box: {box}"})
            continue
        crop = img_rgb[max(y, 0):max(y + h, 0), max(x, 0):max(x + w, 0)]
        results.append(get_color(crop) if crop.size else {"error": "The box holds none of the image"})
    return results

if __name__ == "__main__":
    print(json.dumps(get_colors(sys.argv[1], sys.argv[2:])))