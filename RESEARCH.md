# Offline Tobacco Leaf Grading System
### Technical Research Documentation

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Scope and Leaf Condition Requirement](#2-scope-and-leaf-condition-requirement)
3. [Potential Use Cases](#3-potential-use-cases)
4. [Grade Descriptions](#4-grade-descriptions)
5. [Original Machine Learning Model](#5-original-machine-learning-model)
6. [Server Architecture (Pre-Migration)](#6-server-architecture-pre-migration)
7. [Migration: Server to Offline](#7-migration-server-to-offline)
8. [Model Conversion to TFLite](#8-model-conversion-to-tflite)
9. [Gatekeeper — Pre-Inference Filter](#9-gatekeeper--pre-inference-filter)
10. [Gatekeeper Value Extraction](#10-gatekeeper-value-extraction)
11. [Mobile Application](#11-mobile-application)
12. [Inference Pipeline (End-to-End)](#12-inference-pipeline-end-to-end)
13. [Analytics and Data Export](#13-analytics-and-data-export)
14. [How to Use](#14-how-to-use)
15. [How to Regenerate Gatekeeper Values](#15-how-to-regenerate-gatekeeper-values)
16. [How to Reconvert the Model](#16-how-to-reconvert-the-model)
17. [Project File Structure](#17-project-file-structure)
18. [Dependencies](#18-dependencies)

---

## 1. Project Overview

This system performs automated tobacco leaf grading using a mobile device camera. It operates entirely offline — no internet connection or remote server is required at the point of classification.

The system was originally built as a client-server application where a Flutter mobile app sent captured images to a Python Flask server for classification. The server hosted a two-stage deep learning pipeline: an EfficientNetB3 feature extractor followed by a custom classifier head. The migration replaced this architecture with a fully on-device pipeline using TensorFlow Lite for inference and OpenCV for pre-inference image validation.

Key design goals:
- 100% offline inference on Android and iOS
- Prevent misclassification of non-leaf objects (hands, floor, debris)
- Maintain classification parity with the original server pipeline
- Record and export grading data with location metadata

---

## 2. Scope and Leaf Condition Requirement

The classifier is designed exclusively for **dried tobacco leaves that are ready for sale**. It is not intended for fresh, green, or partially cured leaves.

Dried leaves exhibit the specific color, texture, and shape characteristics that the model was trained on. Attempting to classify undried or partially cured leaves will produce unreliable results, as their HSV color profile and surface texture differ significantly from the training data. The gatekeeper's HSV validation range is calibrated to dried leaf coloration and will reject leaves that fall outside this range.

This scope aligns with the primary use case: grading at the point of delivery, after the curing process is complete and the farmer is preparing to sell.

---

## 3. Potential Use Cases

### Pre-Delivery Sorting at the Farm

The most practical field application is rapid pre-delivery sorting. A farmer can mount or prop the phone at a fixed height over a dark surface — a black cloth, dark mat, or dark floor — and pass dried leaves one at a time under the camera. The automatic detection triggers without any button press, grading each leaf as it is held in the frame.

This workflow allows a single person to sort a batch of dried leaves by grade before transport to a buying warehouse. Leaves can be physically separated into grade piles as the app classifies them, providing a preliminary quality assessment that sets expectations before the official warehouse grading.

This is particularly valuable as a preprocessing step: farmers arrive at the buying station with leaves already sorted by grade, reducing handling time and giving the farmer a documented record of their own pre-assessment.

### Buying Station Verification

At a buying warehouse or collection point, a station operator can use the app to perform a spot-check on incoming batches. The analytics export provides a timestamped, location-tagged record of every classification performed, which can be shared with supervisors or retained for traceability.

### Field Research and Data Collection

Researchers or extension workers can use the app to collect graded leaf data across different farms and regions. The JSON export includes label, confidence, timestamp, and location for every record, making it suitable for aggregating into a larger dataset for model improvement or regional quality analysis.

---

## 4. Grade Descriptions

The classifier outputs one of five grade labels, mapped to descriptive quality tiers and National Tobacco Administration (NTA) grade equivalents. All grades apply to dried, cured tobacco leaves ready for sale.

| Label | Description   | NTA Grade   |
|-------|---------------|-------------|
| AX    | Fine quality  | NTA Grade A |
| BX    | Good quality  | NTA Grade B |
| CX    | Good quality  | NTA Grade C |
| DX    | Fair quality  | NTA Grade D |
| K3    | Good quality  | NTA Grade C |

A minimum softmax confidence of **80%** is required for a classification to be recorded. Results below this threshold are shown to the user with a prompt to reposition the leaf, but are not saved to analytics.

---

## 5. Original Machine Learning Model

### Architecture

The model uses a two-stage pipeline:

**Stage 1 — Feature Extractor**
- Architecture: EfficientNetB3
- Weights: ImageNet (pretrained, frozen)
- Configuration: `include_top=False`, `pooling='avg'`
- Input shape: `(300, 300, 3)` — RGB image
- Output: 1536-dimensional feature vector

**Stage 2 — Classifier Head**
- File: `server/final_model.keras`
- Input: 1536-dimensional feature vector from EfficientNetB3
- Output: Softmax probabilities over 5 classes — `['AX', 'BX', 'CX', 'DX', 'K3']`

### Preprocessing

Images are preprocessed using `tf.keras.applications.efficientnet.preprocess_input`, which applies channel-wise mean subtraction and scaling derived from the ImageNet dataset. This is distinct from a simple `[-1, 1]` rescaling and must be applied consistently — using a different normalization produces near-flat logits (~48% top-class probability regardless of input).

### Training Dataset

The classifier head was trained on feature vectors extracted from a dataset of dried tobacco leaf images captured on a dark floor background. The dataset used for gatekeeper calibration consisted of **148 images**, all used successfully.

---

## 6. Server Architecture (Pre-Migration)

The original deployment used a Python Flask server exposed via ngrok for remote access from the mobile app.

**Port:** 8090  
**Endpoint:** `POST /predict` — accepts a multipart image file, returns JSON with `prediction` and `confidence`

**Server inference flow:**
```
Image (PIL) → resize(300×300) → img_to_array → preprocess_input
    → EfficientNetB3.predict() → feature vector
    → final_model.predict() → argmax → class label + confidence
```

**Limitations of the server approach:**
- Required active internet connection and ngrok tunnel
- Introduced network latency per classification
- Server had to be running and accessible at time of use
- Not viable for field use in areas with poor connectivity

---

## 7. Migration: Server to Offline

### Strategy

Rather than running two separate model calls (feature extractor → classifier), the migration stacks both into a single Keras functional model with the preprocessing baked in as a Lambda layer. This single model is then converted to a `.tflite` file that runs entirely on-device.

### Key Design Decision — Preprocessing Inside the Graph

The `preprocess_input` function is embedded as a Lambda layer inside the Keras model before conversion. This means the mobile app feeds raw `0–255` RGB pixel values directly to the TFLite model, and the graph handles normalization internally — exactly matching the server's behavior.

An alternative approach of applying `[-1, 1]` rescaling in Dart was tested and rejected: it produces incorrect logits with ~48% confidence on the top class regardless of input, because EfficientNetB3 was trained with ImageNet-specific channel statistics, not symmetric rescaling.

### What Was Removed

- `http` package dependency from Flutter
- All server address configuration UI
- Network request/response handling code
- Flask server dependency for runtime operation

### What Was Added

- `tflite_flutter ^0.12.1` — on-device TFLite inference
- `opencv_dart ^1.3.0` — contour detection and shape analysis for the gatekeeper
- Gatekeeper pre-inference filter (see Section 9)
- Dart Isolate processing via `compute()` for background execution

---

## 8. Model Conversion to TFLite

### Process

```
server/final_model.keras  (classifier head)
        +
EfficientNetB3 (ImageNet weights, include_top=False, pooling=avg)
        +
Lambda(efficientnet.preprocess_input)
        ↓
tobacco_end_to_end.keras  (stacked functional model)
        ↓
TFLiteConverter  (DEFAULT quantization + SELECT_TF_OPS)
        ↓
mobile/assets/tobacco_model.tflite
```

### Quantization

Dynamic range quantization is applied. This reduces model size significantly (approximately 50 MB → 12 MB) and improves inference speed on mobile hardware with minimal accuracy impact.

### Flex Ops

`SELECT_TF_OPS` is included alongside `TFLITE_BUILTINS` because the Lambda layer containing `preprocess_input` uses TensorFlow operations not available in the standard TFLite builtin op set.

### Running the Conversion

```bash
# Full end-to-end model (default, recommended)
.venv/bin/python model_converter.py

# Classifier head only (legacy — expects pre-extracted feature vectors)
.venv/bin/python model_converter.py --classifier-only
```

---

## 9. Gatekeeper — Pre-Inference Filter

The gatekeeper is a multi-stage computer vision filter that runs on every camera frame before the TFLite model is invoked. Its purpose is to prevent the classifier from running on non-leaf objects — hands, floor, debris, or any other object in frame — and to enforce that the leaf is correctly positioned and surrounded by a dark background.

All gatekeeper processing runs in a Dart Isolate to avoid blocking the camera preview UI thread.

### Why a Gatekeeper Is Necessary

The TFLite model will always produce a classification output for any input image. Without a pre-filter, every camera frame would be classified and potentially recorded as a grade. The gatekeeper enforces that only frames containing a valid, correctly positioned dried tobacco leaf proceed to inference.

### Pipeline Overview

```
Camera frame (YUV420 → JPEG, sensor-orientation corrected)
        ↓
Stage 0: Dark-background pre-check
        ↓
Stage 1: Otsu foreground segmentation + size check
        ↓
Stage 1b: Centering check (leaf must be near frame centre)
        ↓
Stage 1c: Dark-margin check (leaf must have dark surroundings)
        ↓
Stage 2: HSV color validation
        ↓
Stage 3: Shape validation (solidity + aspect ratio)
        ↓
Stage 4: Crop → resize 300×300 → build input tensor
        ↓
TFLite inference
```

### Stage 0 — Dark Background Pre-Check

Otsu thresholding is adaptive — it always finds a threshold that splits the histogram, even on a uniform wall or hand. Before running Otsu, the scene must be verified to actually contain a dark background.

| Check | Threshold | Purpose |
|-------|-----------|---------|
| Dark pixel ratio | ≥ 20% of frame pixels with luma < 80 | Confirms dark surface is visible |
| Scene median luma | ≤ 140 | Rejects bright rooms with no dark surface |

The training dataset was captured on a floor with a measured background mean brightness of approximately 60.5 (medium grey under daylight). The thresholds accept this range while rejecting brighter environments.

### Stage 1 — Otsu Foreground Segmentation

Mirrors the segmentation used during gatekeeper value extraction.

1. Resize frame to max dimension 800px
2. Convert to grayscale
3. Apply Gaussian blur (5×5 kernel)
4. Apply Otsu's binarization threshold
5. Find external contours, select the largest by area

| Check | Value | Purpose |
|-------|-------|---------|
| Foreground fill ratio | 0.03 – 0.55 | Rejects empty frames and fully-bright scenes |
| Minimum contour area (absolute) | ≥ 1,500 px | Absolute floor |
| Minimum contour area (relative) | ≥ 15% of frame | Rejects small objects; dataset p5 = 22% |

### Stage 1b — Centering Check

The contour's bounding box centroid must fall within the guide region on screen. This prevents classification from triggering when the leaf is at the edge of the frame and not yet properly positioned.

| Axis | Maximum offset from frame centre |
|------|----------------------------------|
| Horizontal | 28% of frame width |
| Vertical | 30% of frame height |

These bounds correspond to the leaf-shaped guide overlay, which is centred at approximately 50% width and 47% height of the screen.

### Stage 1c — Dark Margin Check

A 20-pixel border ring is sampled around the contour's bounding box. At least 55% of those border pixels must be dark (luma < 80). This enforces that the leaf has sufficient dark surroundings on all sides — not just that the overall scene has some dark area. A leaf pushed to the edge of the dark surface where a bright background is adjacent will fail this check.

### Stage 2 — HSV Color Validation

The contour is validated against the dried tobacco leaf HSV color profile extracted from the dataset. At least 55% of bright foreground pixels within the contour bounding box must fall within the expanded HSV range. Only pixels with luma ≥ 40 are counted.

| Channel | Margin applied to dataset values |
|---------|----------------------------------|
| Hue | ± 6 |
| Saturation | ± 15 |
| Value | ± 20 |

### Stage 3 — Shape Validation

| Property | Formula | Threshold |
|----------|---------|-----------|
| Solidity | contour area / convex hull area | ≥ dataset min × 0.95 |
| Aspect ratio | long side / short side (min area rect) | dataset range ± 0.20 |

Solidity measures convexity. Aspect ratio captures the oblong form of a tobacco leaf.

### Stage 4 — Crop and Resize

The bounding rectangle is scaled back to original full-resolution image coordinates, cropped, and resized to 300×300 pixels. Raw `0–255` RGB float values are written into the `[1, 300, 300, 3]` input tensor.

---

## 10. Gatekeeper Value Extraction

The gatekeeper thresholds are derived empirically from the dataset and stored in `mobile/assets/leaf_values.txt`, which is bundled with the app and parsed at runtime. No thresholds are hardcoded.

### Extraction Method

For each image in the dataset:

1. Resize to max dimension 800px
2. Grayscale → Gaussian blur → Otsu threshold
3. Find the largest contour; skip if area < 1,500 px
4. Convert image to HSV
5. Create a filled mask from the contour
6. Collect all HSV pixel values within the mask
7. Compute rotated aspect ratio via minimum area rectangle
8. Compute solidity: `contour_area / convex_hull_area`

### Statistical Aggregation

The 5th and 95th percentiles are used across the full dataset to trim outliers:

```
H_min, H_max  = percentile(all_hue_pixels,    [5, 95])
S_min, S_max  = percentile(all_sat_pixels,    [5, 95])
V_min, V_max  = percentile(all_val_pixels,    [5, 95])
sol_min       = percentile(solidities,         5)
AR_min, AR_max = percentile(aspect_ratios,    [5, 95])
```

### Extracted Values (Current Dataset — 148 images)

```
COLOR (HSV RANGE)
Hue:          14  to  105
Saturation:    9  to  174
Value:        100  to  207

SHAPE (GEOMETRY)
Min Solidity:     0.653
Aspect Ratio:     1.54  to  2.30

DATASET SUMMARY
Images scanned:   148
Leaves used:      148
```

### Runtime Parsing

The app parses `leaf_values.txt` at startup using regex patterns matching each field. Gatekeeper thresholds can be updated by regenerating `leaf_values.txt` from a new dataset and replacing the bundled asset — no code change is required.

---

## 11. Mobile Application

**Framework:** Flutter (Dart SDK ^3.8.1)  
**Package name:** `tob_leaf_classy`  
**Version:** 1.0.0+1  
**Platforms:** Android, iOS

### Key Services

| File | Responsibility |
|------|---------------|
| `lib/services/offline_classifier_service.dart` | Gatekeeper + TFLite inference pipeline |
| `lib/services/app_constants.dart` | Labels, confidence threshold, storage keys |
| `lib/services/classification_analytics_service.dart` | Per-label counters, record storage, JSON export |

### Key Pages

| File | Responsibility |
|------|---------------|
| `lib/main.dart` | Camera stream, live detection, result display |
| `lib/pages/settings_page.dart` | Location input, analytics counters, export/reset |
| `lib/pages/help_page.dart` | User guide |

### Camera Stream and Orientation

The app opens the rear camera at `ResolutionPreset.medium` with `ImageFormatGroup.yuv420`. Each frame is converted from YUV420 to JPEG via manual per-pixel YUV→RGB conversion. The sensor orientation reported by the camera hardware is read at initialization and applied as a rotation to the decoded image before JPEG encoding. This corrects the 90° rotation that Android back camera sensors typically produce relative to portrait orientation, ensuring the result screen preview and the classified image are always correctly oriented.

A frame is skipped if a previous frame is still being processed, preventing queue buildup on slower devices.

### Threading Model

```
Main thread (UI)
    └── Isolate: gatekeeper check (fast path, no tensor build)
            └── if passes → Isolate: full pipeline + TFLite inference
```

---

## 12. Inference Pipeline (End-to-End)

```
Camera frame (YUV420)
    │
    ▼
YUV → RGB conversion + sensor orientation rotation
    │
    ▼
JPEG encode (quality 85)
    │
    ▼
[Isolate] Stage 0: dark pixel ratio + scene median check
    │  reject → discard frame silently
    ▼
[Isolate] Stage 1: Otsu segmentation + contour + size check
    │  reject → discard frame silently
    ▼
[Isolate] Stage 1b: centroid within guide bounds
    │  reject → discard frame silently
    ▼
[Isolate] Stage 1c: dark border margin ≥ 55%
    │  reject → discard frame silently
    ▼
[Isolate] Stage 2: HSV color validation ≥ 55% match
    │  reject → discard frame silently
    ▼
[Isolate] Stage 3: solidity + aspect ratio check
    │  reject → discard frame silently
    ▼
[Isolate] Stage 4: crop → resize 300×300 → float32 tensor [1,300,300,3]
    │
    ▼
TFLite inference (tobacco_model.tflite)
    │  internally: preprocess_input → EfficientNetB3 → classifier head → softmax
    ▼
argmax → predicted label
    │
    ├── confidence < 80% → show result screen, do not record
    │
    └── confidence ≥ 80% → record to analytics → show result screen
```

---

## 13. Analytics and Data Export

Each accepted classification is stored locally with the following fields:

```json
{
  "timestamp": "2025-06-29T14:42:59.000Z",
  "label": "AX",
  "confidence": 0.923,
  "description": "Fine quality",
  "nta_grade": "NTA Grade A",
  "location": "Candon City, Ilocos Sur"
}
```

Per-label counters are maintained separately for fast retrieval. The full export JSON includes schema version, location, label list and legend, per-label counters, total count, full record array, and export timestamp.

Export is available via "Share analytics JSON" (system share sheet) or "Copy analytics JSON" (clipboard) in the Settings page.

---

## 14. How to Use

### Scanning a Leaf

1. Ensure the leaf is **dried and ready for sale** — the classifier is not designed for fresh or partially cured leaves
2. Place a single dried tobacco leaf flat on a **black or dark surface**
3. Open the app — the camera activates automatically
4. Hold the phone over the leaf so it fills the leaf-shaped guide on screen
5. The app detects and grades the leaf automatically — no button press required
6. The result screen shows the grade label, description, NTA grade, and confidence percentage
7. Tap **Scan again** to return to the camera

### Rapid Sorting Workflow

For sorting a batch before delivery:

1. Set up a dark surface (black cloth or dark mat) in a well-lit area
2. Open Settings and set your location before starting
3. Mount or prop the phone at a fixed height over the dark surface
4. Pass dried leaves one at a time under the camera, holding each briefly in the guide
5. Separate leaves into grade piles as the app classifies them
6. When the batch is complete, go to Settings → **Share analytics JSON** to export the session record

### Using a Saved Image

Tap **Pick Image** in the bottom bar to select an image from the device gallery. The same gatekeeper and inference pipeline applies.

### Setting Location

Open Settings and enter the town and province before starting a grading session. This is attached to every classification record in the export.

### Resetting for a New Session

Open Settings → **Reset analytics** to clear all counters and records. This cannot be undone.

---

## 15. How to Regenerate Gatekeeper Values

Run when the dataset is updated or expanded. All images should be of dried tobacco leaves on a dark background.

```bash
# Default — reads from ./dataset, writes to ./leaf_values.txt
.venv/bin/python extract.py

# Custom paths
.venv/bin/python extract.py --dataset /path/to/images --output leaf_values.txt
```

After regeneration, copy the output file to `mobile/assets/leaf_values.txt` and rebuild the app. No code changes are required.

**Requirements:** Python environment with `opencv-python` and `numpy` installed.

---

## 16. How to Reconvert the Model

Run when `server/final_model.keras` is retrained or updated.

```bash
source .venv/bin/activate
python model_converter.py
```

Output is written directly to `mobile/assets/tobacco_model.tflite`. Rebuild the Flutter app to include the updated model.

**macOS note:** If TensorFlow fails to import due to `tensorflow-metal` incompatibility:
```bash
.venv/bin/python -m pip uninstall -y tensorflow-metal
python model_converter.py
```

---

## 17. Project File Structure

```
tobacco-leaf-classification/
│
├── server/
│   ├── server.py                        # Original Flask inference server
│   ├── final_model.keras                # Trained classifier head
│   ├── final_model_end_to_end.keras     # Stacked model (generated by converter)
│   ├── requirements.txt
│   └── Dockerfile
│
├── mobile/
│   ├── assets/
│   │   ├── tobacco_model.tflite         # Quantized TFLite model (bundled)
│   │   └── leaf_values.txt              # Gatekeeper thresholds (bundled)
│   └── lib/
│       ├── main.dart                    # App entry, camera UI, result display
│       ├── pages/
│       │   ├── settings_page.dart       # Location, analytics, export
│       │   └── help_page.dart           # User guide
│       └── services/
│           ├── offline_classifier_service.dart   # Gatekeeper + TFLite pipeline
│           ├── app_constants.dart                # Labels, thresholds, keys
│           └── classification_analytics_service.dart  # Storage and export
│
├── dataset/                             # Calibration images (148 dried leaf JPEGs)
├── extract.py                           # Gatekeeper value extraction script
├── model_converter.py                   # Keras → TFLite conversion script
└── leaf_values.txt                      # Root copy of gatekeeper values
```

---

## 18. Dependencies

### Python (server + tooling)

| Package | Purpose |
|---------|---------|
| tensorflow | Model training, conversion, server inference |
| flask / flask-cors | Original HTTP inference server |
| numpy | Array operations |
| Pillow | Image loading and resizing |
| opencv-python | Gatekeeper value extraction |

### Flutter (mobile)

| Package | Version | Purpose |
|---------|---------|---------|
| tflite_flutter | ^0.12.1 | On-device TFLite inference |
| opencv_dart | ^1.3.0 | Contour detection, shape analysis |
| camera | ^0.11.0+2 | Live camera stream |
| image | ^4.2.0 | YUV→RGB conversion, rotation, JPEG encode, crop/resize |
| image_picker | ^1.0.7 | Gallery image selection |
| shared_preferences | ^2.2.2 | Local analytics storage |
| share_plus | ^10.0.0 | System share sheet for data export |

---

*Last updated to reflect: gatekeeper centering and dark-margin checks (Stage 1b/1c), camera sensor orientation correction, leaf condition scope (dried leaves only), and rapid sorting workflow.*
