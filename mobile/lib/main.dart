import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import 'pages/help_page.dart';
import 'pages/settings_page.dart';
import 'services/app_constants.dart';
import 'services/classification_analytics_service.dart';
import 'services/offline_classifier_service.dart';

void main() {
  runApp(const TobaccoClassifierApp());
}

class TobaccoClassifierApp extends StatelessWidget {
  const TobaccoClassifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Leaf Identifier',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  File? _imageFile;
  String _resultText = '';
  String _confidenceText = '';
  bool _loading = false;
  int _totalClassifications = 0;

  final ImagePicker _picker = ImagePicker();
  late final OfflineClassifierService _offlineClassifier;
  final ClassificationAnalyticsService _analyticsService =
      ClassificationAnalyticsService();
  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  CameraController? _cameraController;
  int _cameraSensorOrientation = 0;
  bool _cameraReady = false;
  /// True after [availableCameras] + [initialize] + stream attempt finishes (success or failure).
  bool _cameraInitComplete = false;
  bool _isProcessingFrame = false;
  bool _classificationLocked = false;
  bool _showGuideHint = true;
  _CameraFullscreenData? _cameraFullscreen;
  bool _streamPausedForResult = false;

  @override
  void initState() {
    super.initState();
    _offlineClassifier = OfflineClassifierService()..initialize();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );
    _hideGuideHintLater();
    _loadCounter();
    _initializeCamera();
  }

  Future<void> _hideGuideHintLater() async {
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    setState(() => _showGuideHint = false);
  }

  Future<void> _loadCounter() async {
    final total = await _analyticsService.getTotalClassifications();
    if (!mounted) return;
    setState(() => _totalClassifications = total);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _offlineClassifier.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraInitComplete = true);
        }
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      // Ensure autofocus is enabled for near-field leaf capture.
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
      } catch (_) {}
      await controller.startImageStream(_onCameraFrame);
      if (!mounted) return;
      setState(() {
        _cameraController = controller;
        _cameraSensorOrientation = back.sensorOrientation;
        _cameraReady = true;
        _cameraInitComplete = true;
      });
    } catch (_) {
      // Keep UI functional (gallery path) even if camera stream fails.
      if (mounted) {
        setState(() => _cameraInitComplete = true);
      }
    }
  }

  Future<void> _onCameraFrame(CameraImage frame) async {
    if (_isProcessingFrame || _loading || _classificationLocked) return;
    _isProcessingFrame = true;
    try {
      final jpgBytes = _cameraImageToJpeg(frame);
      if (jpgBytes == null) return;

      final gatePassed = await _offlineClassifier.gatekeeperPassesBytes(
        jpgBytes,
      );
      if (!gatePassed) return;

      _classificationLocked = true;
      setState(() {
        _loading = true;
        _imageFile = null;
      });

      final output = await _offlineClassifier.classifyBytes(jpgBytes);
      if (!mounted) return;

      if (!output.gatePassed) {
        setState(() {
          _classificationLocked = false;
          _loading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not confirm leaf — try again'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (output.error != null) {
        try {
          await _cameraController?.stopImageStream();
        } catch (_) {}
        _streamPausedForResult = true;
        setState(() {
          _loading = false;
          _cameraFullscreen = _CameraFullscreenData(
            previewBytes: jpgBytes,
            title: 'Analysis failed',
            body: output.error!,
            kind: _CameraFullscreenKind.error,
          );
        });
        return;
      }

      final prediction = output.prediction ?? 'Unknown';
      final confidence = output.confidence ?? 0;

      if (confidence < AppConstants.minClassificationConfidence) {
        try {
          await _cameraController?.stopImageStream();
        } catch (_) {}
        _streamPausedForResult = true;
        setState(() {
          _loading = false;
          _cameraFullscreen = _CameraFullscreenData(
            previewBytes: jpgBytes,
            title: 'Confidence too low',
            body:
                'Best match ${(confidence * 100).toStringAsFixed(1)}% — need at least ${(AppConstants.minClassificationConfidence * 100).toStringAsFixed(0)}% to record a grade. Ensure the leaf is on a dark surface.',
            kind: _CameraFullscreenKind.lowConfidence,
          );
        });
        return;
      }

      await _analyticsService.recordClassification(
        label: prediction,
        confidence: confidence,
      );
      await _loadCounter();
      final legend = labelLegend[prediction];
      final detailed = legend == null
          ? prediction
          : '$prediction - ${legend.description} (${legend.ntaGrade})';

      try {
        await _cameraController?.stopImageStream();
      } catch (_) {}
      _streamPausedForResult = true;
      setState(() {
        _loading = false;
        _cameraFullscreen = _CameraFullscreenData(
          previewBytes: jpgBytes,
          title: detailed,
          body: '${(confidence * 100).toStringAsFixed(1)}% confidence',
          kind: _CameraFullscreenKind.success,
        );
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _classificationLocked = false;
          _loading = false;
        });
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _resumeCameraScanning() async {
    if (!mounted) return;
    setState(() {
      _cameraFullscreen = null;
      _resultText = '';
      _confidenceText = '';
      _loading = false;
    });
    _classificationLocked = false;
    _fadeController.reset();
    _slideController.reset();
    if (!_streamPausedForResult) return;
    final c = _cameraController;
    if (c != null && c.value.isInitialized && _cameraReady) {
      try {
        await c.startImageStream(_onCameraFrame);
        _streamPausedForResult = false;
      } catch (_) {}
    }
  }

  Uint8List? _cameraImageToJpeg(CameraImage image) {
    if (image.format.group != ImageFormatGroup.yuv420 ||
        image.planes.length < 3) {
      return null;
    }
    final width = image.width;
    final height = image.height;
    final imgBuf = img.Image(width: width, height: height);

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final uvX = x ~/ 2;
        final uvY = y ~/ 2;
        final yIndex = y * yPlane.bytesPerRow + x;
        final uvIndex = uvY * uPlane.bytesPerRow + uvX * uPlane.bytesPerPixel!;

        final yp = yPlane.bytes[yIndex];
        final up = uPlane.bytes[uvIndex];
        final vp = vPlane.bytes[uvIndex];

        final r = (yp + 1.402 * (vp - 128)).round().clamp(0, 255);
        final g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128))
            .round()
            .clamp(0, 255);
        final b = (yp + 1.772 * (up - 128)).round().clamp(0, 255);

        imgBuf.setPixelRgb(x, y, r, g, b);
      }
    }

    // Rotate to match screen orientation.
    // Android back camera sensor is typically 90° rotated relative to portrait.
    final rotated = switch (_cameraSensorOrientation) {
      90  => img.copyRotate(imgBuf, angle: 90),
      180 => img.copyRotate(imgBuf, angle: 180),
      270 => img.copyRotate(imgBuf, angle: 270),
      _   => imgBuf,
    };

    return Uint8List.fromList(img.encodeJpg(rotated, quality: 85));
  }

  Future<void> _getImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() {
      _imageFile = File(picked.path);
      _loading = true;
    });
    await _runOfflinePipeline(_imageFile!);
  }

  Future<void> _runOfflinePipeline(File imageFile) async {
    try {
      final output = await _offlineClassifier.classify(imageFile);
      if (!mounted) return;
      if (!output.gatePassed) {
        setState(() {
          _resultText = 'No tobacco detected';
          _confidenceText = 'Gatekeeper rejected';
        });
      } else if (output.error != null) {
        setState(() {
          _resultText = 'Analysis failed';
          _confidenceText = output.error!;
        });
      } else {
        final prediction = output.prediction ?? 'Unknown';
        final confidence = output.confidence ?? 0;
        if (confidence < AppConstants.minClassificationConfidence) {
          setState(() {
            _resultText = 'Confidence too low';
            _confidenceText =
                'Best match ${(confidence * 100).toStringAsFixed(1)}% — need ${(AppConstants.minClassificationConfidence * 100).toStringAsFixed(0)}% or higher to record.';
          });
        } else {
          await _analyticsService.recordClassification(
            label: prediction,
            confidence: confidence,
          );
          await _loadCounter();
          final legend = labelLegend[prediction];
          final detailed = legend == null
              ? prediction
              : '$prediction - ${legend.description} (${legend.ntaGrade})';
          setState(() {
            _resultText = detailed;
            _confidenceText = '${(confidence * 100).toStringAsFixed(1)}%';
          });
        }
      }
      _fadeController.forward(from: 0);
      _slideController.forward(from: 0);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openHelp() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HelpPage()));
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) return;
    await _loadCounter();
    if (!mounted) return;
    if (updated == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _reset() {
    if (_streamPausedForResult) {
      unawaited(_resumeCameraScanning());
      return;
    }
    setState(() {
      _imageFile = null;
      _loading = false;
      _resultText = '';
      _confidenceText = '';
      _cameraFullscreen = null;
    });
    _classificationLocked = false;
    _fadeController.reset();
    _slideController.reset();
  }

  bool get _isError =>
      _resultText.toLowerCase().contains('failed') ||
      _resultText.toLowerCase().contains('error');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_cameraFullscreen != null)
            _buildCameraFullscreenResult()
          else if (_imageFile == null)
            _buildCameraView()
          else
            _buildResultView(),
        ],
      ),
    );
  }

  Widget _buildCameraFullscreenResult() {
    final data = _cameraFullscreen!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Image.memory(data.previewBytes, fit: BoxFit.cover),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0.88),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: _resumeCameraScanning,
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      data.kind == _CameraFullscreenKind.success
                          ? Icons.check_circle
                          : data.kind == _CameraFullscreenKind.lowConfidence
                              ? Icons.help_outline
                              : Icons.error_outline,
                      color: data.kind == _CameraFullscreenKind.success
                          ? const Color(0xFF4CAF50)
                          : Colors.white70,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      data.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      data.body,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 16,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _resumeCameraScanning,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Scan again',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraView() {
    if (_cameraReady && _cameraController != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _LeafGuidePainter(),
            ),
          ),
          if (_showGuideHint)
            Positioned(
              top: 110,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Place leaf on dark surface for instant detection',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Gallery picker
                  GestureDetector(
                    onTap: () => _getImage(ImageSource.gallery),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Select Image',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Counter pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '$_totalClassifications scanned',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  // Help + Settings
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _openHelp,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.help_outline_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _openSettings,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.settings_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    // While the live preview is starting, avoid flashing the legacy gallery/camera picker UI.
    if (!_cameraInitComplete) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
              ),
              SizedBox(height: 20),
              Text(
                'Starting camera…',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // No camera or init failed: legacy picker-only screen (gallery + one-shot camera).
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1a1a1a), Color(0xFF2d2d2d)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          const Icon(
            Icons.camera_alt_outlined,
            size: 80,
            color: Colors.white70,
          ),
          const SizedBox(height: 30),
          const Text(
            'Identify Tobacco Leaves',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Capture or select an image to analyze',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
            child: Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () => _getImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () => _getImage(ImageSource.camera),
                    isPrimary: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isPrimary
              ? const Color(0xFF4CAF50)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView() {
    return Stack(
      children: [
        SizedBox.expand(child: Image.file(_imageFile!, fit: BoxFit.cover)),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.45,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
            ),
            child: _loading ? _buildLoadingState() : _buildResultState(),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
          ),
          const SizedBox(height: 20),
          Text(
            'Analyzing leaf...',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultState() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: _isError ? Colors.red : const Color(0xFF4CAF50),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isError ? 'Analysis Failed' : 'Analysis Complete',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Classification: $_resultText',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Confidence: $_confidenceText',
                style: const TextStyle(fontSize: 16),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(child: _button('Try Again', _reset, false)),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _button(
                      'New Image',
                      () => _getImage(ImageSource.camera),
                      true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap, bool primary) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFF4CAF50) : Colors.grey[100],
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: primary ? Colors.white : Colors.grey[700],
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

enum _CameraFullscreenKind { success, lowConfidence, error }

class _CameraFullscreenData {
  final Uint8List previewBytes;
  final String title;
  final String body;
  final _CameraFullscreenKind kind;

  const _CameraFullscreenData({
    required this.previewBytes,
    required this.title,
    required this.body,
    required this.kind,
  });
}

class _LeafGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.47);
    final leafHeight = size.height * 0.72;
    final leafWidth = leafHeight * 0.40;

    final path = Path();
    path.moveTo(center.dx, center.dy - leafHeight / 2);
    path.cubicTo(
      center.dx + leafWidth,
      center.dy - leafHeight * 0.25,
      center.dx + leafWidth,
      center.dy + leafHeight * 0.25,
      center.dx,
      center.dy + leafHeight / 2,
    );
    path.cubicTo(
      center.dx - leafWidth,
      center.dy + leafHeight * 0.25,
      center.dx - leafWidth,
      center.dy - leafHeight * 0.25,
      center.dx,
      center.dy - leafHeight / 2,
    );

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF7CFF7C).withValues(alpha: 0.9);
    canvas.drawPath(path, outlinePaint);

    final dashedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.55);
    final dashPath = Path();
    const dashLen = 10.0;
    const dashGap = 8.0;
    for (
      double y = center.dy - leafHeight * 0.38;
      y < center.dy + leafHeight * 0.38;
      y += dashLen + dashGap
    ) {
      dashPath.moveTo(center.dx, y);
      dashPath.lineTo(
        center.dx,
        math.min(y + dashLen, center.dy + leafHeight * 0.38),
      );
    }
    canvas.drawPath(dashPath, dashedPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
