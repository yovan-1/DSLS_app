import 'advisory.dart';
import 'friction_model.dart';
import 'sight_distance_model.dart';

/// Which of the four constraints produced the recommendation.
///
/// Surfacing this is what lets the UI say *"65 — limited by headlight range"*
/// instead of an unexplained number. A driver who understands why the app is
/// asking them to slow down is far more likely to comply.
enum BindingConstraint {
  /// The posted or curated limit — conditions imposed no further reduction.
  postedLimit,

  /// Stopping distance versus how far ahead the driver can see.
  sightDistance,

  /// Available grip on the current surface.
  grip,

  /// Uncertainty margin applied to an unverified limit.
  inferredLimitMargin,
}

/// The result of a speed evaluation.
class SpeedRecommendation {
  /// Recommended speed in km/h. Never exceeds the ceiling it was given.
  final int recommendedSpeedKph;

  /// The ceiling the recommendation was measured against.
  final int speedLimitKph;

  /// Which constraint bound the result.
  final BindingConstraint bindingConstraint;

  /// How far ahead the driver can see, and why that is the number.
  final SightDistance sightDistance;

  /// Inferred road-surface state.
  final SurfaceState surface;

  /// How much the conditions have eroded the safe speed, 0–100.
  ///
  /// 0 means conditions impose no reduction at all — unlike the previous model,
  /// whose risk score bottomed out at 30 and called a quiet residential street
  /// at noon "MEDIUM".
  final int conditionRisk;

  /// True when conditions are bad enough that the honest advice is to stop
  /// rather than to crawl.
  final bool stopRecommended;

  final List<Advisory> advisories;

  const SpeedRecommendation({
    required this.recommendedSpeedKph,
    required this.speedLimitKph,
    required this.bindingConstraint,
    required this.sightDistance,
    required this.surface,
    required this.conditionRisk,
    required this.stopRecommended,
    required this.advisories,
  });

  RiskBand get riskBand => RiskBand.forScore(conditionRisk);

  /// Short human-readable explanation of the binding constraint, for the UI.
  String get bindingReason {
    switch (bindingConstraint) {
      case BindingConstraint.postedLimit:
        return 'Posted limit';
      case BindingConstraint.sightDistance:
        switch (sightDistance.limiter) {
          case SightLimiter.headlights:
            return 'Limited by headlight range';
          case SightLimiter.weather:
            return 'Limited by visibility';
          case SightLimiter.measuredLight:
            return 'Limited by measured light';
          case SightLimiter.unrestricted:
            return 'Limited by sight distance';
        }
      case BindingConstraint.grip:
        return 'Limited by road grip (${FrictionModel.label(surface)})';
      case BindingConstraint.inferredLimitMargin:
        return 'No mapped limit — conservative estimate';
    }
  }
}

/// Risk bands over a 0–100 scale that genuinely spans its range.
enum RiskBand {
  low,
  moderate,
  high,
  severe;

  static RiskBand forScore(int score) {
    if (score >= 75) return RiskBand.severe;
    if (score >= 50) return RiskBand.high;
    if (score >= 25) return RiskBand.moderate;
    return RiskBand.low;
  }

  String get label {
    switch (this) {
      case RiskBand.low:
        return 'LOW';
      case RiskBand.moderate:
        return 'MODERATE';
      case RiskBand.high:
        return 'HIGH';
      case RiskBand.severe:
        return 'SEVERE';
    }
  }
}
