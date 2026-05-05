import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../models/pressure_calibration.dart';
import '../models/pressure_reading.dart';
import '../theme/app_theme.dart';

class PressureIndicator extends StatelessWidget {
  final PressureReading reading;
  final PressureCalibration calibration;

  const PressureIndicator({
    super.key,
    required this.reading,
    required this.calibration,
  });

  @override
  Widget build(BuildContext context) {
    final pct = reading.adjusted.clamp(0.0, 1.0).toDouble();
    final fillColor = _colorFor(reading.state);

    return SizedBox(
      width: 48,
      child: Column(
        children: [
          Text(
            '${reading.percent.round()}',
            maxLines: 1,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              width: 24,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.card, width: 2),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 90),
                        width: double.infinity,
                        height: constraints.maxHeight * pct,
                        decoration: BoxDecoration(
                          color: fillColor,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(10),
                          ),
                        ),
                      ),
                      _ThresholdLine(
                        bottom:
                            constraints.maxHeight *
                            calibration.warningPressureThreshold,
                        color: AppColors.warning.withValues(alpha: 0.72),
                      ),
                      _ThresholdLine(
                        bottom:
                            constraints.maxHeight *
                            calibration.failPressureThreshold,
                        color: AppColors.danger.withValues(alpha: 0.82),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          RotatedBox(
            quarterTurns: 3,
            child: Text(
              I18n.t('pressure'),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.muted,
                letterSpacing: 0,
              ),
            ),
          ),
          if (reading.isFallback) ...[
            const SizedBox(height: 6),
            const Text(
              'Safe\nTouch\nMode',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                height: 1.05,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (kDebugMode) ...[
            const SizedBox(height: 6),
            Text(
              'r ${reading.raw.toStringAsFixed(2)}\nn ${reading.normalized.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 8,
                height: 1.1,
                color: AppColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _colorFor(PressureState state) {
    switch (state) {
      case PressureState.safe:
        return AppColors.trailGreen;
      case PressureState.warning:
        return AppColors.trailYellow;
      case PressureState.tooStrong:
        return AppColors.trailRed;
    }
  }
}

class _ThresholdLine extends StatelessWidget {
  final double bottom;
  final Color color;

  const _ThresholdLine({required this.bottom, required this.color});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: bottom,
      left: 0,
      right: 0,
      child: Container(height: 2, color: color),
    );
  }
}
