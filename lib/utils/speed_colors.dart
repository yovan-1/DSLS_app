import 'package:flutter/material.dart';

import '../models/speed_model/speed_recommendation.dart';

/// Presentation rules for speed and risk.
///
/// These used to live inside `GpsSpeedService`, which meant a `ChangeNotifier`
/// was handing out `Colors.yellow`, and the same green/amber/red thresholds
/// were re-implemented in `SpeedScreen`. Colour is a UI concern; keeping it in
/// one place stops the two copies drifting apart.
class SpeedColors {
  const SpeedColors._();

  /// How far over the recommendation counts as "slightly over" rather than
  /// clearly over.
  static const int cautionMarginKph = 10;

  /// Colour for the speedometer given the current and recommended speeds.
  static Color forSpeed({
    required int currentSpeed,
    required int recommendedSpeed,
  }) {
    if (currentSpeed == 0) return Colors.grey;
    final diff = currentSpeed - recommendedSpeed;
    if (diff <= 0) return Colors.green;
    if (diff <= cautionMarginKph) return Colors.amber;
    return Colors.red;
  }

  /// Colour for a risk band.
  static Color forRiskBand(RiskBand band) {
    switch (band) {
      case RiskBand.low:
        return Colors.green;
      case RiskBand.moderate:
        return Colors.amber;
      case RiskBand.high:
        return Colors.orange;
      case RiskBand.severe:
        return Colors.red;
    }
  }
}
