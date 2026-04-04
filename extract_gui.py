import argparse
import os

import cv2
import numpy as np


WINDOW_NAME = "Tobacco Leaf Validator (OpenCV)"


def _noop(_value):
    return None


def _resize_for_ui(img, max_dim=700):
    h, w = img.shape[:2]
    scale = max_dim / max(h, w)
    if scale >= 1.0:
        return img
    return cv2.resize(img, (int(w * scale), int(h * scale)))


def _create_trackbars():
    cv2.namedWindow(WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(WINDOW_NAME, 1300, 700)
    cv2.createTrackbar("Low H", WINDOW_NAME, 10, 179, _noop)
    cv2.createTrackbar("High H", WINDOW_NAME, 35, 179, _noop)
    cv2.createTrackbar("Low S", WINDOW_NAME, 50, 255, _noop)
    cv2.createTrackbar("High S", WINDOW_NAME, 255, 255, _noop)
    cv2.createTrackbar("Low V", WINDOW_NAME, 50, 255, _noop)
    cv2.createTrackbar("High V", WINDOW_NAME, 255, 255, _noop)


def _read_hsv_bounds():
    low_h = cv2.getTrackbarPos("Low H", WINDOW_NAME)
    high_h = cv2.getTrackbarPos("High H", WINDOW_NAME)
    low_s = cv2.getTrackbarPos("Low S", WINDOW_NAME)
    high_s = cv2.getTrackbarPos("High S", WINDOW_NAME)
    low_v = cv2.getTrackbarPos("Low V", WINDOW_NAME)
    high_v = cv2.getTrackbarPos("High V", WINDOW_NAME)
    l_hsv = np.array([min(low_h, high_h), min(low_s, high_s), min(low_v, high_v)])
    h_hsv = np.array([max(low_h, high_h), max(low_s, high_s), max(low_v, high_v)])
    return l_hsv, h_hsv


def _rotated_aspect_ratio(contour):
    (_, _), (w, h), _ = cv2.minAreaRect(contour)
    short_side = max(1.0, min(w, h))
    long_side = max(w, h)
    return long_side / short_side


def run(image_path):
    if not image_path or not os.path.exists(image_path):
        raise FileNotFoundError(f"Image not found: {image_path}")

    img = cv2.imread(image_path)
    if img is None:
        raise RuntimeError(f"Could not read image: {image_path}")
    img = _resize_for_ui(img)

    _create_trackbars()

    while True:
        low_hsv, high_hsv = _read_hsv_bounds()

        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        mask = cv2.inRange(hsv, low_hsv, high_hsv)
        display = img.copy()

        ar_text = "-"
        sol_text = "-"
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if contours:
            cnt = max(contours, key=cv2.contourArea)
            if cv2.contourArea(cnt) > 500:
                x, y, w, h = cv2.boundingRect(cnt)
                ar = _rotated_aspect_ratio(cnt)
                hull = cv2.convexHull(cnt)
                hull_area = cv2.contourArea(hull)
                sol = cv2.contourArea(cnt) / hull_area if hull_area > 0 else 0
                ar_text = f"{ar:.2f}"
                sol_text = f"{sol:.3f}"
                cv2.drawContours(display, [cnt], -1, (0, 255, 0), 2)
                cv2.rectangle(display, (x, y), (x + w, y + h), (255, 180, 0), 1)

        mask_3ch = cv2.cvtColor(mask, cv2.COLOR_GRAY2BGR)
        combined = np.hstack((display, mask_3ch))
        cv2.putText(combined, f"AR: {ar_text}", (20, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 255), 2)
        cv2.putText(combined, f"Sol: {sol_text}", (20, 70), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 255), 2)
        cv2.putText(
            combined,
            "Press q/ESC to quit",
            (20, combined.shape[0] - 20),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (220, 220, 220),
            1,
        )
        cv2.imshow(WINDOW_NAME, combined)

        key = cv2.waitKey(30) & 0xFF
        if key in (27, ord("q")):
            break

    cv2.destroyAllWindows()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="HSV and shape tuner for tobacco leaf segmentation.")
    parser.add_argument("--image", default="", help="Path to a leaf image.")
    args = parser.parse_args()

    image_path = args.image.strip()
    if not image_path:
        image_path = input("Enter image path: ").strip()

    try:
        run(image_path)
    except Exception as exc:
        print(f"Error: {exc}")
        print("Try: python3 extract_gui.py --image dataset/<your-image>.jpg")