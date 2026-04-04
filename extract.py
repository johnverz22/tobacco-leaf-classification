import argparse
from pathlib import Path

import cv2
import numpy as np


IMAGE_EXTENSIONS = ("*.jpg", "*.jpeg", "*.png", "*.bmp", "*.webp")
OUTPUT_FILE = "leaf_values.txt"
MAX_UI_DIM = 800
MIN_LEAF_AREA = 1500


def resize_for_consistency(img, max_dim=MAX_UI_DIM):
    h, w = img.shape[:2]
    scale = max_dim / max(h, w)
    if scale >= 1.0:
        return img
    return cv2.resize(img, (int(w * scale), int(h * scale)))


def collect_images(dataset_dir):
    root = Path(dataset_dir)
    image_paths = []
    for ext in IMAGE_EXTENSIONS:
        image_paths.extend(root.rglob(ext))
    return sorted(image_paths)


def extract_leaf_contour(img_bgr):
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    _, thresh = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    cnt = max(contours, key=cv2.contourArea)
    if cv2.contourArea(cnt) < MIN_LEAF_AREA:
        return None
    return cnt


def rotated_aspect_ratio(contour):
    (_, _), (w, h), _ = cv2.minAreaRect(contour)
    short_side = max(1.0, min(w, h))
    long_side = max(w, h)
    return long_side / short_side


def build_gatekeeper(dataset_dir, output_file):
    image_paths = collect_images(dataset_dir)
    print(f"Processing {len(image_paths)} images from {dataset_dir} ...")

    h_pixels, s_pixels, v_pixels = [], [], []
    solidities, aspect_ratios = [], []
    used = 0

    for image_path in image_paths:
        img = cv2.imread(str(image_path))
        if img is None:
            continue

        img = resize_for_consistency(img)
        cnt = extract_leaf_contour(img)
        if cnt is None:
            continue

        used += 1
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        mask = np.zeros(img.shape[:2], dtype=np.uint8)
        cv2.drawContours(mask, [cnt], -1, 255, -1)

        pixels = hsv[mask > 0]
        if pixels.size == 0:
            continue

        # Pixel-level color distribution tracks GUI tuning better than per-image mean HSV.
        h_pixels.extend(pixels[:, 0].tolist())
        s_pixels.extend(pixels[:, 1].tolist())
        v_pixels.extend(pixels[:, 2].tolist())

        ar = rotated_aspect_ratio(cnt)
        area = cv2.contourArea(cnt)
        hull = cv2.convexHull(cnt)
        hull_area = cv2.contourArea(hull)
        sol = float(area) / hull_area if hull_area > 0 else 0.0

        aspect_ratios.append(ar)
        solidities.append(sol)

    if not h_pixels or not aspect_ratios or not solidities:
        print("Error: No valid leaf contours detected. Check dataset images/backgrounds.")
        return False

    # 5th/95th trims outliers while keeping a practical gate.
    h_min, h_max = np.percentile(h_pixels, [5, 95])
    s_min, s_max = np.percentile(s_pixels, [5, 95])
    v_min, v_max = np.percentile(v_pixels, [5, 95])
    sol_min = np.percentile(solidities, 5)
    ar_min, ar_max = np.percentile(aspect_ratios, [5, 95])

    with open(output_file, "w", encoding="utf-8") as f:
        f.write("=== TOBACCO LEAF GATEKEEPER VALUES ===\n")
        f.write("Use these to filter non-tobacco objects in Flutter.\n\n")
        f.write("COLOR (HSV RANGE)\n")
        f.write(f"Hue:        {int(h_min)} to {int(h_max)}\n")
        f.write(f"Saturation: {int(s_min)} to {int(s_max)}\n")
        f.write(f"Value:      {int(v_min)} to {int(v_max)}\n\n")
        f.write("SHAPE (GEOMETRY)\n")
        f.write(f"Min Solidity:     {sol_min:.3f}\n")
        f.write(f"Aspect Ratio:     {ar_min:.2f} to {ar_max:.2f}\n\n")
        f.write("DATASET SUMMARY\n")
        f.write(f"Images scanned:   {len(image_paths)}\n")
        f.write(f"Leaves used:      {used}\n")
        f.write(
            "\nNote: Solidity below Min or Aspect Ratio outside range => likely NOT a leaf."
        )

    print(f"Success! Values saved to {output_file} (used {used}/{len(image_paths)} images)")
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract tobacco leaf gatekeeper values from dataset.")
    parser.add_argument("--dataset", default="dataset", help="Dataset directory path.")
    parser.add_argument("--output", default=OUTPUT_FILE, help="Output text file.")
    args = parser.parse_args()

    build_gatekeeper(dataset_dir=args.dataset, output_file=args.output)