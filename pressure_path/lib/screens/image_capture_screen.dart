import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../i18n/strings.dart';
import '../models/editable_path.dart';
import '../services/edge_detection_service.dart';
import '../theme/app_theme.dart';
import 'path_editor_screen.dart';

class ImageCaptureScreen extends StatefulWidget {
  const ImageCaptureScreen({super.key});

  @override
  State<ImageCaptureScreen> createState() => _ImageCaptureScreenState();
}

class _ImageCaptureScreenState extends State<ImageCaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _imageBytes;
  File? _imageFile;
  bool _isProcessing = false;
  EdgeDetectionResult? _detectionResult;
  double _sensitivity = 0.20;
  Timer? _debounce;

  Future<void> _pickImage(ImageSource source) async {
    final xFile = await _picker.pickImage(source: source, maxWidth: 1200, maxHeight: 1200);
    if (xFile == null) return;

    final file = File(xFile.path);
    final bytes = await file.readAsBytes();

    setState(() {
      _imageFile = file;
      _imageBytes = bytes;
      _detectionResult = null;
    });

    _runDetection();
  }

  Future<void> _runDetection() async {
    if (_imageFile == null) return;
    setState(() => _isProcessing = true);

    try {
      final result = await EdgeDetectionService.detect(
        _imageFile!,
        highThreshold: _sensitivity,
        minPathLength: 15,
      );
      if (mounted) {
        setState(() {
          _detectionResult = result;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _onSensitivityChanged(double value) {
    setState(() => _sensitivity = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _runDetection();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(I18n.t('createFromPhoto')),
      ),
      body: _imageBytes == null ? _buildPickerUI() : _buildPreviewUI(),
    );
  }

  Widget _buildPickerUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Camera icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.2),
                    AppColors.accent.withValues(alpha: 0.05),
                  ],
                ),
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 48, color: AppColors.accent),
            ),
            const SizedBox(height: 32),

            // Take Photo button
            SizedBox(
              width: 280,
              child: ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: 20),
                label: Text(I18n.t('takePhoto')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Gallery button
            SizedBox(
              width: 280,
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded, size: 20),
                label: Text(I18n.t('chooseGallery')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Tip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lightbulb_outline, size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      I18n.t('photoTip'),
                      style: const TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewUI() {
    final pathCount = _detectionResult?.paths.length ?? 0;

    return Column(
      children: [
        // Image preview with edge overlay
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Dimmed original image
                  Opacity(
                    opacity: 0.35,
                    child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                  ),

                  // Edge overlay
                  if (_detectionResult != null)
                    CustomPaint(
                      painter: _EdgeOverlayPainter(
                        result: _detectionResult!,
                        imageBytes: _imageBytes!,
                      ),
                    ),

                  // Loading shimmer
                  if (_isProcessing)
                    Container(
                      color: Colors.black26,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: AppColors.accent),
                            const SizedBox(height: 12),
                            Text(I18n.t('detectingEdges'),
                                style: const TextStyle(color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ),

                  // Path count badge
                  if (!_isProcessing && _detectionResult != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          I18n.t('foundPaths').replaceAll('%d', '$pathCount'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Sensitivity slider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(I18n.t('edgeSensitivity'),
                  style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              Expanded(
                child: Slider(
                  value: _sensitivity,
                  min: 0.08,
                  max: 0.40,
                  onChanged: _onSensitivityChanged,
                ),
              ),
              Text(
                _sensitivity.toStringAsFixed(2),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),

        // No edges message
        if (!_isProcessing && _detectionResult != null && pathCount == 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(I18n.t('noEdges'),
                        style: const TextStyle(fontSize: 13, color: AppColors.warning)),
                  ),
                ],
              ),
            ),
          ),

        // Bottom actions
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Row(
            children: [
              // Change image
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _imageBytes = null;
                      _imageFile = null;
                      _detectionResult = null;
                    });
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(I18n.t('cancel')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.muted,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Edit Paths
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _detectionResult != null && pathCount > 0
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PathEditorScreen(
                                imageBytes: _imageBytes!,
                                detectionResult: _detectionResult!,
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.edit, size: 18),
                  label: Text(I18n.t('editPaths')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    disabledBackgroundColor: AppColors.card,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EdgeOverlayPainter extends CustomPainter {
  final EdgeDetectionResult result;
  final Uint8List imageBytes;

  _EdgeOverlayPainter({required this.result, required this.imageBytes});

  @override
  void paint(Canvas canvas, Size size) {
    if (result.paths.isEmpty || result.imageSize == Size.zero) return;

    final sx = size.width / result.imageSize.width;
    final sy = size.height / result.imageSize.height;
    final scale = sx < sy ? sx : sy;
    final ox = (size.width - result.imageSize.width * scale) / 2;
    final oy = (size.height - result.imageSize.height * scale) / 2;

    for (int pi = 0; pi < result.paths.length; pi++) {
      final path = result.paths[pi];
      if (path.length < 2) continue;

      final color = kEditorPalette[pi % kEditorPalette.length];
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final drawPath = Path();
      drawPath.moveTo(
        ox + path[0].dx * scale,
        oy + path[0].dy * scale,
      );
      for (int i = 1; i < path.length; i++) {
        drawPath.lineTo(
          ox + path[i].dx * scale,
          oy + path[i].dy * scale,
        );
      }
      canvas.drawPath(drawPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeOverlayPainter oldDelegate) {
    return result != oldDelegate.result;
  }
}
