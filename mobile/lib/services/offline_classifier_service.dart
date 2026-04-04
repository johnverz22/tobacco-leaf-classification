import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'app_constants.dart';

class OfflineInferenceOutput {
  final bool gatePassed;
  final String? prediction;
  final double? confidence;
  final String? error;

  const OfflineInferenceOutput({
    required this.gatePassed,
    this.prediction,
    this.confidence,
    this.error,
  });
}

class GatekeeperConfig {
  final int hMin;
  final int hMax;
  final int sMin;
  final int sMax;
  final int vMin;
  final int vMax;
  final double minSolidity;
  final double arMin;
  final double arMax;

  const GatekeeperConfig({
    required this.hMin,
    required this.hMax,
    required this.sMin,
    required this.sMax,
    required this.vMin,
    required this.vMax,
    required this.minSolidity,
    required this.arMin,
    required this.arMax,
  });
}

class OfflineClassifierService {
  static const String _modelAsset = 'assets/tobacco_model.tflite';
  static const String _leafValuesAsset = 'assets/leaf_values.txt';
  static const int _modelInputSize = 300;
  static const List<String> _labels = AppConstants.labels;

  // ── Stage 0: Dark-background pre-check ───────────────────────────────────
  // Otsu is adaptive — it ALWAYS finds a split, even on a uniform wall/hand.
  // We must verify the scene actually has a dark background before trusting
  // the Otsu contour. Dataset bg_mean ≈ 60 (medium grey floor under daylight).
  // Reject the frame if the scene median is too bright (no dark floor present)
  // or if there is not enough dark area to provide contrast.

  /// Max median frame brightness (grayscale 0–255). Scenes brighter than this
  /// have no dark background — Otsu will produce garbage contours.
  static const int _maxSceneMedian = 140;

  /// Minimum fraction of frame pixels that are "dark" (V < this value in HSV).
  /// Ensures a dark floor is actually visible in the frame.
  static const int _darkPixelVThreshold = 80;
  static const double _minDarkPixelRatio = 0.20;

  // ── Stage 1: Otsu foreground segmentation ────────────────────────────────
  /// Foreground fill ratio after Otsu. Uniform scenes produce ratio≈1.0 when
  /// otsu_threshold=0; the tight upper bound catches that.
  static const double _minFgFillRatio = 0.03;
  static const double _maxFgFillRatio = 0.55;

  /// Minimum contour area as a fraction of the total frame area.
  /// Dataset p5 = 22% — using 15% gives tolerance for slightly distant leaves
  /// while firmly rejecting small objects (coins, debris, fingertips).
  /// Absolute pixel floor is kept as a secondary sanity check only.
  static const double _minContourFillRatio = 0.15;
  static const double _minContourArea = 1500.0; // absolute fallback only

  /// We resize to this before Otsu — matches extract.py MAX_UI_DIM=800 logic.
  static const int _segResizeDim = 800;

  // ── Stage 2: HSV color validation on the found contour ───────────────────
  // Confirms the bright blob is a tobacco leaf, not a hand/shoe/paper.
  // Margins are tight — we already have the isolated contour.
  static const int _hMargin = 6;
  static const int _sMargin = 15;
  static const int _vMargin = 20;

  /// Fraction of contour pixels that must pass HSV check.
  /// Raised from 0.30 — tobacco leaves are consistently coloured;
  /// skin/wood/concrete rarely hit 55% within the leaf HSV range.
  static const double _minLeafColorFraction = 0.55;

  // ── Stage 1b / 1c: Centering + dark-margin checks ────────────────────────
  /// The contour centroid must fall within this fractional distance from the
  /// frame centre on each axis. Matches the guide which sits at cx=0.50,
  /// cy=0.47 with half-width ≈ 0.29 and half-height ≈ 0.36 of the frame.
  static const double _maxCentroidOffsetX = 0.28; // fraction of frame width
  static const double _maxCentroidOffsetY = 0.30; // fraction of frame height

  /// A border of this many pixels (in seg-space) around the contour bounding
  /// box is sampled. The fraction of those border pixels that are dark must
  /// meet _minBorderDarkRatio — ensures the leaf has dark surroundings.
  static const int _borderSampleWidth = 20;
  static const double _minBorderDarkRatio = 0.55;

  // ── Stage 3: Shape validation ─────────────────────────────────────────────
  static const double _solidityRelax = 0.95;
  static const double _arPadding = 0.20;

  Interpreter? _interpreter;
  GatekeeperConfig? _config;

  Future<void> initialize() async {
    _interpreter ??= await Interpreter.fromAsset(_modelAsset);
    _config ??= await _loadGatekeeperConfig();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  Future<OfflineInferenceOutput> classify(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return classifyBytes(bytes);
  }

  Future<OfflineInferenceOutput> classifyBytes(Uint8List bytes) async {
    try {
      await initialize();
      final prep = await compute(
        _preprocessForInference,
        _PreprocessArgs(bytes, _config!, true),
      );
      if (!prep.gatePassed) {
        return const OfflineInferenceOutput(gatePassed: false);
      }

      final input = prep.inputTensor!;
      final output = List.generate(1, (_) => List.filled(_labels.length, 0.0));
      _interpreter!.run(input, output);
      final probs = output.first;

      var best = 0;
      for (var i = 1; i < probs.length; i++) {
        if (probs[i] > probs[best]) best = i;
      }

      final prediction = best < _labels.length ? _labels[best] : 'Unknown';
      return OfflineInferenceOutput(
        gatePassed: true,
        prediction: prediction,
        confidence: probs[best],
      );
    } catch (e) {
      return OfflineInferenceOutput(gatePassed: true, error: e.toString());
    }
  }

  Future<bool> gatekeeperPassesBytes(Uint8List bytes) async {
    try {
      await initialize();
      final prep = await compute(
        _preprocessForInference,
        _PreprocessArgs(bytes, _config!, false),
      );
      return prep.gatePassed;
    } catch (_) {
      return false;
    }
  }

  Future<GatekeeperConfig> _loadGatekeeperConfig() async {
    final raw = await rootBundle.loadString(_leafValuesAsset);
    final hue = RegExp(r'Hue:\s+(\d+)\s+to\s+(\d+)').firstMatch(raw);
    final sat = RegExp(r'Saturation:\s+(\d+)\s+to\s+(\d+)').firstMatch(raw);
    final val = RegExp(r'Value:\s+(\d+)\s+to\s+(\d+)').firstMatch(raw);
    final sol = RegExp(r'Min Solidity:\s+([0-9.]+)').firstMatch(raw);
    final ar = RegExp(
      r'Aspect Ratio:\s+([0-9.]+)\s+to\s+([0-9.]+)',
    ).firstMatch(raw);
    if (hue == null ||
        sat == null ||
        val == null ||
        sol == null ||
        ar == null) {
      throw StateError('Invalid leaf_values.txt');
    }
    return GatekeeperConfig(
      hMin: int.parse(hue.group(1)!),
      hMax: int.parse(hue.group(2)!),
      sMin: int.parse(sat.group(1)!),
      sMax: int.parse(sat.group(2)!),
      vMin: int.parse(val.group(1)!),
      vMax: int.parse(val.group(2)!),
      minSolidity: double.parse(sol.group(1)!),
      arMin: double.parse(ar.group(1)!),
      arMax: double.parse(ar.group(2)!),
    );
  }
}

class _PreprocessArgs {
  final Uint8List bytes;
  final GatekeeperConfig cfg;
  final bool buildTensor;
  const _PreprocessArgs(this.bytes, this.cfg, this.buildTensor);
}

class _PreprocessResult {
  final bool gatePassed;
  final List<List<List<List<double>>>>? inputTensor;
  const _PreprocessResult({required this.gatePassed, this.inputTensor});
}

_PreprocessResult _preprocessForInference(_PreprocessArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return const _PreprocessResult(gatePassed: false);

  // ── Stage 0: Dark-background pre-check ───────────────────────────────────
  // Otsu always finds a split — even on a uniform wall. We must confirm the
  // scene actually has a dark floor before trusting the Otsu contour.
  final scale = OfflineClassifierService._segResizeDim /
      math.max(decoded.width, decoded.height);
  final segW = (decoded.width * math.min(scale, 1.0)).round();
  final segH = (decoded.height * math.min(scale, 1.0)).round();
  final segImg = img.copyResize(decoded, width: segW, height: segH);

  final totalPx = segW * segH;
  final lumaValues = List<int>.filled(totalPx, 0);
  var darkCount = 0;
  for (var y = 0; y < segH; y++) {
    for (var x = 0; x < segW; x++) {
      final p = segImg.getPixel(x, y);
      final luma = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
      lumaValues[y * segW + x] = luma;
      // Count dark pixels using HSV-V equivalent (luma ≈ V for this purpose)
      if (luma < OfflineClassifierService._darkPixelVThreshold) darkCount++;
    }
  }

  // Reject if not enough dark area (no dark floor visible)
  final darkRatio = darkCount / totalPx;
  if (darkRatio < OfflineClassifierService._minDarkPixelRatio) {
    return const _PreprocessResult(gatePassed: false);
  }

  // Reject if scene median is too bright (bright room, no dark floor)
  final sorted = List<int>.from(lumaValues)..sort();
  final medianLuma = sorted[totalPx ~/ 2];
  if (medianLuma > OfflineClassifierService._maxSceneMedian) {
    return const _PreprocessResult(gatePassed: false);
  }

  // ── Stage 1: Otsu foreground segmentation ────────────────────────────────
  // Reuse lumaValues already computed above for the grayscale Mat.
  final grayBytes = Uint8List(segW * segH);
  for (var i = 0; i < lumaValues.length; i++) {
    grayBytes[i] = lumaValues[i].clamp(0, 255);
  }
  final grayMat = cv.Mat.fromList(segH, segW, cv.MatType.CV_8UC1, grayBytes);

  // GaussianBlur then Otsu — identical to extract.py
  final blurred = cv.gaussianBlur(grayMat, (5, 5), 0);
  final (_, thresh) = cv.threshold(
    blurred,
    0,
    255,
    cv.THRESH_BINARY | cv.THRESH_OTSU,
  );
  grayMat.dispose();
  blurred.dispose();

  // Foreground fill ratio check — rejects empty frames and fully-bright scenes
  var fgCount = 0;
  final threshData = thresh.data;
  for (var i = 0; i < threshData.length; i++) {
    if (threshData[i] > 0) fgCount++;
  }
  final fgRatio = fgCount / totalPx;
  if (fgRatio < OfflineClassifierService._minFgFillRatio ||
      fgRatio > OfflineClassifierService._maxFgFillRatio) {
    thresh.dispose();
    return const _PreprocessResult(gatePassed: false);
  }

  // Find largest contour in the Otsu mask
  final (contours, _) = cv.findContours(
    thresh,
    cv.RETR_EXTERNAL,
    cv.CHAIN_APPROX_SIMPLE,
  );
  thresh.dispose();

  if (contours.isEmpty) return const _PreprocessResult(gatePassed: false);

  var cnt = contours.first;
  var area = cv.contourArea(cnt);
  for (final c in contours) {
    final a = cv.contourArea(c);
    if (a > area) {
      area = a;
      cnt = c;
    }
  }
  if (area < OfflineClassifierService._minContourArea ||
      area / totalPx < OfflineClassifierService._minContourFillRatio) {
    return const _PreprocessResult(gatePassed: false);
  }

  // ── Stage 1b: Centering check ─────────────────────────────────────────────
  // The contour centroid must be near the frame centre to match the on-screen
  // guide. A leaf at the very edge of the frame is not properly positioned.
  final br = cv.boundingRect(cnt);
  final centroidX = br.x + br.width / 2.0;
  final centroidY = br.y + br.height / 2.0;
  final frameCx = segW / 2.0;
  final frameCy = segH / 2.0;
  final offsetX = (centroidX - frameCx).abs() / segW;
  final offsetY = (centroidY - frameCy).abs() / segH;
  if (offsetX > OfflineClassifierService._maxCentroidOffsetX ||
      offsetY > OfflineClassifierService._maxCentroidOffsetY) {
    return const _PreprocessResult(gatePassed: false);
  }

  // ── Stage 1c: Dark-margin check ───────────────────────────────────────────
  // Sample a border ring around the contour bounding box. The majority of
  // those pixels must be dark — confirming the leaf has dark surroundings and
  // is not butted against a bright edge or another object.
  final bw = OfflineClassifierService._borderSampleWidth;
  var borderTotal = 0;
  var borderDark = 0;

  void _sampleBorderPixel(int px, int py) {
    if (px < 0 || py < 0 || px >= segW || py >= segH) {
      borderDark++; // out-of-frame pixels count as dark (they are black)
      borderTotal++;
      return;
    }
    borderTotal++;
    if (lumaValues[py * segW + px] < OfflineClassifierService._darkPixelVThreshold) {
      borderDark++;
    }
  }

  // Top and bottom strips
  for (var x = br.x - bw; x < br.x + br.width + bw; x++) {
    for (var dy = 1; dy <= bw; dy++) {
      _sampleBorderPixel(x, br.y - dy);
      _sampleBorderPixel(x, br.y + br.height + dy - 1);
    }
  }
  // Left and right strips (excluding corners already counted)
  for (var y = br.y; y < br.y + br.height; y++) {
    for (var dx = 1; dx <= bw; dx++) {
      _sampleBorderPixel(br.x - dx, y);
      _sampleBorderPixel(br.x + br.width + dx - 1, y);
    }
  }

  if (borderTotal > 0 &&
      borderDark / borderTotal < OfflineClassifierService._minBorderDarkRatio) {
    return const _PreprocessResult(gatePassed: false);
  }

  // ── Stage 2: HSV color validation on contour pixels ───────────────────────
  // Confirms the bright blob is a tobacco leaf, not a hand/shoe/white paper.
  // br is already declared above in Stage 1b.
  final cfg = args.cfg;
  final lowH = (cfg.hMin - OfflineClassifierService._hMargin).clamp(0, 179);
  final highH = (cfg.hMax + OfflineClassifierService._hMargin).clamp(0, 179);
  final lowS = (cfg.sMin - OfflineClassifierService._sMargin).clamp(0, 255);
  final highS = (cfg.sMax + OfflineClassifierService._sMargin).clamp(0, 255);
  final lowV = (cfg.vMin - OfflineClassifierService._vMargin).clamp(0, 255);
  final highV = (cfg.vMax + OfflineClassifierService._vMargin).clamp(0, 255);

  // Sample pixels inside the bounding rect of the contour (on the seg-scaled image)
  var contourPixels = 0;
  var leafColorPixels = 0;
  final rx = br.x.clamp(0, segW - 1);
  final ry = br.y.clamp(0, segH - 1);
  final rx2 = (br.x + br.width).clamp(0, segW);
  final ry2 = (br.y + br.height).clamp(0, segH);
  for (var py = ry; py < ry2; py++) {
    for (var px = rx; px < rx2; px++) {
      final p = segImg.getPixel(px, py);
      // Only count pixels that are bright foreground (inside the Otsu mask region)
      final luma = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      if (luma < 40) continue; // skip dark background pixels in bbox
      contourPixels++;
      final hsv = _rgbToHsv(p.r, p.g, p.b);
      if (hsv.$1 >= lowH &&
          hsv.$1 <= highH &&
          hsv.$2 >= lowS &&
          hsv.$2 <= highS &&
          hsv.$3 >= lowV &&
          hsv.$3 <= highV) {
        leafColorPixels++;
      }
    }
  }

  if (contourPixels == 0) return const _PreprocessResult(gatePassed: false);
  final colorFraction = leafColorPixels / contourPixels;
  if (colorFraction < OfflineClassifierService._minLeafColorFraction) {
    return const _PreprocessResult(gatePassed: false);
  }

  // ── Stage 3: Shape validation (solidity + aspect ratio) ───────────────────
  final hull = cv.convexHull(cnt, returnPoints: true);
  final hullPoints = cv.VecPoint.fromMat(hull);
  final hullArea = cv.contourArea(hullPoints);
  final solidity = hullArea <= 0 ? 0.0 : area / hullArea;
  final rr = cv.minAreaRect(cnt);
  final ar = math.max(rr.size.width, rr.size.height) /
      math.max(1.0, math.min(rr.size.width, rr.size.height));

  final shapePassed =
      solidity >= (cfg.minSolidity * OfflineClassifierService._solidityRelax) &&
      ar >= (cfg.arMin - OfflineClassifierService._arPadding) &&
      ar <= (cfg.arMax + OfflineClassifierService._arPadding);

  hullPoints.dispose();
  hull.dispose();

  if (!shapePassed) return const _PreprocessResult(gatePassed: false);
  if (!args.buildTensor) return const _PreprocessResult(gatePassed: true);

  // ── Stage 4: Crop to bounding rect on the ORIGINAL full-res image ─────────
  // Scale the seg-space bounding rect back to original image coordinates.
  final invScale = 1.0 / math.min(scale, 1.0);
  final ox = (br.x * invScale).round().clamp(0, decoded.width - 1);
  final oy = (br.y * invScale).round().clamp(0, decoded.height - 1);
  final ow = (br.width * invScale).round().clamp(1, decoded.width - ox);
  final oh = (br.height * invScale).round().clamp(1, decoded.height - oy);

  final cropped = img.copyCrop(decoded, x: ox, y: oy, width: ow, height: oh);
  final resized = img.copyResize(
    cropped,
    width: OfflineClassifierService._modelInputSize,
    height: OfflineClassifierService._modelInputSize,
  );

  final tensor = List.generate(
    1,
    (_) => List.generate(
      OfflineClassifierService._modelInputSize,
      (ty) => List.generate(OfflineClassifierService._modelInputSize, (tx) {
        final p = resized.getPixel(tx, ty);
        // TFLite graph applies keras efficientnet.preprocess_input; feed 0–255 RGB float.
        return <double>[p.r.toDouble(), p.g.toDouble(), p.b.toDouble()];
      }),
    ),
  );

  return _PreprocessResult(gatePassed: true, inputTensor: tensor);
}

(int, int, int) _rgbToHsv(num rIn, num gIn, num bIn) {
  final r = rIn / 255.0;
  final g = gIn / 255.0;
  final b = bIn / 255.0;
  final cMax = math.max(r, math.max(g, b));
  final cMin = math.min(r, math.min(g, b));
  final delta = cMax - cMin;

  double h = 0.0;
  if (delta != 0) {
    if (cMax == r) {
      h = 60 * (((g - b) / delta) % 6);
    } else if (cMax == g) {
      h = 60 * (((b - r) / delta) + 2);
    } else {
      h = 60 * (((r - g) / delta) + 4);
    }
  }
  if (h < 0) h += 360;
  final s = cMax == 0 ? 0.0 : delta / cMax;
  final v = cMax;

  final hOpenCv = (h / 2).round().clamp(0, 179);
  final sOpenCv = (s * 255).round().clamp(0, 255);
  final vOpenCv = (v * 255).round().clamp(0, 255);
  return (hOpenCv, sOpenCv, vOpenCv);
}
