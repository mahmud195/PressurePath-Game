import 'dart:math';
import 'package:flutter/material.dart';
import '../i18n/strings.dart';
import '../models/pressure_calibration.dart';
import '../models/pressure_reading.dart';
import '../models/trail_path.dart';
import '../services/pressure_input_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pressure_indicator.dart';

class GameScreen extends StatefulWidget {
  final TrailPath? customTrail;
  static double globalTolerance = 35.0;
  static double globalStrokeWidth = 6.0;

  const GameScreen({super.key, this.customTrail});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _GameState { picking, playing, failed, success }

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  _GameState _state = _GameState.picking;
  String _selectedPath = 'wave';
  List<Offset> _pathPoints = [];
  final List<_TrailPoint> _userTrail = [];
  final List<double> _pressureHistory = [];
  final PressureInputService _pressureInput = PressureInputService();
  PressureCalibration _pressureCalibration =
      PressureCalibration.fallbackCalibration();
  PressureReading _pressureReading = PressureReading.zero();
  int _attemptCount = 0;
  double _bestAvgPressure = double.infinity;
  bool _isDrawing = false;
  int _furthestIdx = 0;
  DateTime? _sessionStart;
  bool _muted = false;

  Size _canvasSize = Size.zero;

  // Track the "start hint" pulse animation
  bool _showStartHint = true;

  // Grace period: track how long pressure has been over threshold
  DateTime? _overThresholdSince;
  static const _failGraceMs = 320;

  @override
  void initState() {
    super.initState();
    if (widget.customTrail != null) {
      _selectedPath = 'custom';
    }
    _loadPressureCalibration();
  }

  Future<void> _loadPressureCalibration() async {
    final saved = await PressureInputService.loadCalibration();
    if (!mounted) return;
    final effective = saved.isCalibrated
        ? saved
        : PressureCalibration.fallbackCalibration(
            selectedDifficulty: saved.selectedDifficulty,
          ).copyWith(sensitivityMultiplier: saved.sensitivityMultiplier);

    _pressureInput.updateCalibration(effective);
    setState(() {
      _pressureCalibration = effective;
      _pressureReading = PressureReading.zero(effective);
    });
  }

  void _startPlaying() {
    setState(() {
      _state = _GameState.playing;
      _attemptCount++;
      _userTrail.clear();
      _pressureHistory.clear();
      _furthestIdx = 0;
      _isDrawing = false;
      _pressureInput.reset();
      _pressureReading = PressureReading.zero(_pressureCalibration);
      _showStartHint = true;
      _overThresholdSince = null;
      _sessionStart = DateTime.now();

      if (widget.customTrail != null) {
        _pathPoints = widget.customTrail!.points;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_canvasSize != Size.zero) {
            setState(() {
              final trail = TrailPath.fromType(
                _selectedPath,
                _canvasSize.width,
                _canvasSize.height,
              );
              _pathPoints = trail.points;
            });
          }
        });
      }
    });
  }

  void _triggerFail({String? reason}) {
    if (_state != _GameState.playing) return;
    setState(() {
      _state = _GameState.failed;
      _isDrawing = false;
      _overThresholdSince = null;
    });
    final msgs = I18n.empathyMessages;
    final msg = msgs[Random().nextInt(msgs.length)];
    final fullMsg = reason != null ? '$reason\n$msg' : msg;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(fullMsg, textAlign: TextAlign.center),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _startPlaying();
    });
  }

  void _triggerSuccess() {
    if (_state != _GameState.playing) return;
    final avgP = _pressureHistory.isEmpty
        ? 0.0
        : _pressureHistory.reduce((a, b) => a + b) / _pressureHistory.length;
    if (avgP < _bestAvgPressure) _bestAvgPressure = avgP;
    final elapsed =
        DateTime.now().difference(_sessionStart!).inMilliseconds / 1000;

    setState(() {
      _state = _GameState.success;
      _isDrawing = false;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          I18n.t('successTitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              I18n.t('successMsg'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            _ResultRow(I18n.t('totalAttempts'), '$_attemptCount'),
            _ResultRow(I18n.t('avgPressure'), '${avgP.round()}'),
            _ResultRow(I18n.t('timeTaken'), '${elapsed.toStringAsFixed(1)}s'),
            _ResultRow(I18n.t('bestPressure'), '${_bestAvgPressure.round()}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startPlaying();
            },
            child: Text(I18n.t('playAgain')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(I18n.t('home')),
          ),
        ],
      ),
    );
  }

  Color _trailColor(double p100) {
    final adjusted = p100 / 100.0;
    if (adjusted < _pressureCalibration.warningPressureThreshold) {
      return AppColors.trailGreen;
    }
    if (adjusted < _pressureCalibration.failPressureThreshold) {
      return AppColors.trailYellow;
    }
    return AppColors.trailRed;
  }

  void _onPointerDown(PointerDownEvent e, Size canvasSize) {
    if (_state != _GameState.playing || _pathPoints.isEmpty) return;
    final pos = e.localPosition;
    final startPt = _pathPoints.first;

    // Use a generous tap area: 50px or 8% of canvas width, whichever is larger
    final startRadius = max(50.0, canvasSize.width * 0.08);

    if ((pos - startPt).distance < startRadius) {
      setState(() {
        _isDrawing = true;
        _showStartHint = false;
        _userTrail.clear();
        _furthestIdx = 0;
        _overThresholdSince = null;
      });
    }

    // Always update live pressure on touch
    _updateLivePressure(e);
  }

  void _onPointerMove(PointerMoveEvent e, Size canvasSize) {
    if (_state != _GameState.playing || _pathPoints.isEmpty) return;

    final reading = _updateLivePressure(e);

    if (!_isDrawing) return;

    final pos = e.localPosition;
    final p100 = reading.percent;
    _pressureHistory.add(p100);

    // Find nearest point on path
    double minD = double.infinity;
    int nearestIdx = 0;
    for (int i = 0; i < _pathPoints.length; i++) {
      final d = (pos - _pathPoints[i]).distance;
      if (d < minD) {
        minD = d;
        nearestIdx = i;
      }
    }

    if (nearestIdx > _furthestIdx) _furthestIdx = nearestIdx;

    setState(() {
      _userTrail.add(_TrailPoint(pos, p100, _trailColor(p100)));
    });

    // Pressure fail check with a short grace period.
    if (reading.state == PressureState.tooStrong) {
      _overThresholdSince ??= DateTime.now();
      final elapsed = DateTime.now()
          .difference(_overThresholdSince!)
          .inMilliseconds;
      if (elapsed >= _failGraceMs) {
        _triggerFail();
        return;
      }
    } else {
      _overThresholdSince = null;
    }

    // Fail if went off the path
    if (minD > GameScreen.globalTolerance) {
      _triggerFail(reason: I18n.t('offTrack'));
      return;
    }

    // Check if near end
    final endPt = _pathPoints.last;
    if ((pos - endPt).distance < 25 &&
        _furthestIdx > _pathPoints.length * 0.7) {
      _triggerSuccess();
    }
  }

  void _onPointerUp(PointerUpEvent _) {
    _endPointerGesture();
  }

  void _endPointerGesture() {
    _isDrawing = false;
    _pressureInput.endGesture();
    setState(() {
      _pressureReading = PressureReading.zero(_pressureCalibration);
    });
  }

  /// Update live pressure reading and gauge on every pointer event.
  PressureReading _updateLivePressure(PointerEvent e) {
    final reading = _pressureInput.read(e);
    setState(() {
      _pressureReading = reading;
    });
    return reading;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bg, AppColors.surface],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _SmallIconBtn(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Column(
                      children: [
                        Text(
                          '$_attemptCount',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          I18n.t('attempts'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _SmallIconBtn(
                      icon: _muted ? Icons.volume_off : Icons.volume_up,
                      onTap: () => setState(() => _muted = !_muted),
                    ),
                  ],
                ),
              ),

              // Game body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      // Canvas
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 30,
                                  spreadRadius: -5,
                                  offset: Offset(0, 0),
                                ),
                              ],
                            ),
                            child: _state == _GameState.picking
                                ? _buildPathPicker()
                                : _buildGameCanvas(),
                          ),
                        ),
                      ),

                      // Pressure gauge
                      const SizedBox(width: 8),
                      PressureIndicator(
                        reading: _pressureReading,
                        calibration: _pressureCalibration,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPathPicker() {
    final types = ['wave', 'zigzag', 'spiral'];
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.customTrail == null) ...[
              Text(
                I18n.t('choosePath'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: types.map((t) {
                  final selected = t == _selectedPath;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedPath = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 80,
                      height: 80,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? AppColors.accent
                              : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: AppColors.accent.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 16,
                                ),
                              ]
                            : null,
                      ),
                      child: CustomPaint(painter: _PathPreviewPainter(t)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],

            Text(
              I18n.t('precision'),
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            SizedBox(
              width: 200,
              child: Slider(
                value: GameScreen.globalTolerance,
                min: 2,
                max: 60,
                activeColor: AppColors.accent,
                onChanged: (v) =>
                    setState(() => GameScreen.globalTolerance = v),
              ),
            ),
            Text(
              GameScreen.globalTolerance < 10
                  ? I18n.t('strict')
                  : GameScreen.globalTolerance > 45
                  ? I18n.t('relaxed')
                  : I18n.t('normal'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            Text(
              I18n.t('thickness'),
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            SizedBox(
              width: 200,
              child: Slider(
                value: GameScreen.globalStrokeWidth,
                min: 2,
                max: 24,
                activeColor: AppColors.trailYellow,
                onChanged: (v) =>
                    setState(() => GameScreen.globalStrokeWidth = v),
              ),
            ),
            Text(
              '${GameScreen.globalStrokeWidth.round()} px',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _startPlaying,
              child: Text(I18n.t('startTrace')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Generate path points if empty and we have a canvas size
        if (_pathPoints.isEmpty &&
            _canvasSize != Size.zero &&
            widget.customTrail == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              final trail = TrailPath.fromType(
                _selectedPath,
                _canvasSize.width,
                _canvasSize.height,
              );
              _pathPoints = trail.points;
            });
          });
        }

        return Stack(
          children: [
            // Main interactive canvas
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _onPointerDown(e, _canvasSize),
              onPointerMove: (e) => _onPointerMove(e, _canvasSize),
              onPointerUp: _onPointerUp,
              onPointerCancel: (_) => _endPointerGesture(),
              child: CustomPaint(
                size: _canvasSize,
                painter: _GameCanvasPainter(
                  pathPoints: _pathPoints,
                  userTrail: _userTrail,
                  showStartHint: _showStartHint,
                ),
              ),
            ),

            // Sensor badge — bottom left
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _pressureReading.isFallback
                      ? 'Safe Touch Mode'
                      : I18n.t('sensorActive'),
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ),
            ),

            // "Tap the green dot" hint for first-time
            if (_showStartHint && _pathPoints.isNotEmpty)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      I18n.isArabic
                          ? 'المس الدائرة الخضراء للبدء'
                          : 'Touch the green dot to start',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TrailPoint {
  final Offset position;
  final double pressure;
  final Color color;
  const _TrailPoint(this.position, this.pressure, this.color);
}

class _GameCanvasPainter extends CustomPainter {
  final List<Offset> pathPoints;
  final List<_TrailPoint> userTrail;
  final bool showStartHint;

  _GameCanvasPainter({
    required this.pathPoints,
    required this.userTrail,
    this.showStartHint = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pathPoints.isEmpty) return;

    // Path glow
    final glowPaint = Paint()
      ..color = AppColors.pathGlow
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final pathPath = Path();
    pathPath.moveTo(pathPoints[0].dx, pathPoints[0].dy);
    for (int i = 1; i < pathPoints.length; i++) {
      pathPath.lineTo(pathPoints[i].dx, pathPoints[i].dy);
    }
    canvas.drawPath(pathPath, glowPaint);

    // Path line
    final linePaint = Paint()
      ..color = const Color(0x59636AF1)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(pathPath, linePaint);

    // Start dot — larger pulsing circle when showing hint
    final startCenter = pathPoints.first;
    if (showStartHint) {
      // Outer pulse ring
      canvas.drawCircle(
        startCenter,
        22,
        Paint()
          ..color = AppColors.success.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        startCenter,
        16,
        Paint()
          ..color = AppColors.success.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawCircle(startCenter, 12, Paint()..color = AppColors.success);
    final startText = TextPainter(
      text: const TextSpan(
        text: 'S',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    startText.paint(
      canvas,
      startCenter - Offset(startText.width / 2, startText.height / 2),
    );

    // End dot
    final endCenter = pathPoints.last;
    canvas.drawCircle(endCenter, 12, Paint()..color = AppColors.accent);
    final endText = TextPainter(
      text: const TextSpan(
        text: '★',
        style: TextStyle(color: Colors.white, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    endText.paint(
      canvas,
      endCenter - Offset(endText.width / 2, endText.height / 2),
    );

    // User trail
    for (int i = 1; i < userTrail.length; i++) {
      final prev = userTrail[i - 1];
      final cur = userTrail[i];
      final trailPaint = Paint()
        ..color = cur.color
        ..strokeWidth = GameScreen.globalStrokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(prev.position, cur.position, trailPaint);
    }

    // Cursor glow on last point
    if (userTrail.isNotEmpty) {
      final last = userTrail.last;
      canvas.drawCircle(
        last.position,
        8,
        Paint()..color = last.color.withValues(alpha: 0.27),
      );
      canvas.drawCircle(last.position, 4, Paint()..color = last.color);
    }
  }

  @override
  bool shouldRepaint(covariant _GameCanvasPainter oldDelegate) => true;
}

class _PathPreviewPainter extends CustomPainter {
  final String type;
  _PathPreviewPainter(this.type);

  @override
  void paint(Canvas canvas, Size size) {
    final trail = TrailPath.fromType(
      type,
      size.width,
      size.height,
      numPoints: 50,
    );
    if (trail.points.isEmpty) return;

    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(trail.points[0].dx, trail.points[0].dy);
    for (int i = 1; i < trail.points.length; i++) {
      path.lineTo(trail.points[i].dx, trail.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SmallIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  const _ResultRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ],
      ),
    );
  }
}
