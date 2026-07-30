import 'dart:math' as math;

/// Stopping-distance physics.
///
/// This is the anchor for the whole speed model: rather than inventing
/// percentages, every reduction the app recommends traces back to the standard
/// relation traffic engineers use for stopping sight distance (SSD).
///
/// ```
/// d = v·t_r  +  v² / (2·g·(f ± G))
/// ```
///
/// * `v`   — speed, m/s
/// * `t_r` — perception–reaction time, s
/// * `g`   — gravitational acceleration, m/s²
/// * `f`   — coefficient of longitudinal friction (see FrictionModel)
/// * `G`   — grade (uphill positive); 0 until road elevation data is available
///
/// Reference: AASHTO, *A Policy on Geometric Design of Highways and Streets*
/// ("Green Book"), Ch. 3 — Stopping Sight Distance.
class StoppingDistance {
  const StoppingDistance._();

  /// Gravitational acceleration, m/s².
  static const double gravity = 9.81;

  /// Perception–reaction time in seconds.
  ///
  /// AASHTO's design value for the driving population, not the ~1.0 s a alert
  /// driver achieves in a laboratory. Using the design value is deliberate: the
  /// app must be safe for a distracted driver, not just an ideal one.
  static const double perceptionReactionSeconds = 2.5;

  static double _kphToMps(double kph) => kph / 3.6;
  static double _mpsToKph(double mps) => mps * 3.6;

  /// Total distance in metres needed to stop from [speedKph], comprising the
  /// distance covered during perception–reaction plus the braking distance.
  static double stoppingDistanceMetres(
    double speedKph, {
    required double friction,
    double grade = 0,
  }) {
    if (speedKph <= 0) return 0;
    final v = _kphToMps(speedKph);
    final effectiveFriction = math.max(friction + grade, 0.05);
    return (v * perceptionReactionSeconds) +
        (v * v) / (2 * gravity * effectiveFriction);
  }

  /// The inverse: the highest speed in km/h from which a driver can still stop
  /// within [sightDistanceMetres].
  ///
  /// Solving `v·t_r + v²/(2·g·f) = S` for v gives
  /// `v = −g·f·t_r + sqrt((g·f·t_r)² + 2·g·f·S)`.
  static double maxSpeedForSightDistance(
    double sightDistanceMetres, {
    required double friction,
    double grade = 0,
  }) {
    if (sightDistanceMetres <= 0) return 0;
    final effectiveFriction = math.max(friction + grade, 0.05);
    final gf = gravity * effectiveFriction;
    final b = gf * perceptionReactionSeconds;
    final v = -b + math.sqrt((b * b) + (2 * gf * sightDistanceMetres));
    return _mpsToKph(math.max(v, 0));
  }
}
