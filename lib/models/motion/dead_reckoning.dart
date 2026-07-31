import 'dart:math' as math;

/// Minimal immutable 3-vector.
///
/// Hand-rolled rather than pulled from `vector_math`: that package reaches this
/// project only as a transitive dependency of Flutter, and the four operations
/// needed here are not worth taking a direct dependency for.
class Vector3 {
  final double x;
  final double y;
  final double z;

  const Vector3(this.x, this.y, this.z);

  static const zero = Vector3(0, 0, 0);

  double get magnitude => math.sqrt(x * x + y * y + z * z);

  Vector3 operator +(Vector3 other) =>
      Vector3(x + other.x, y + other.y, z + other.z);

  Vector3 operator -(Vector3 other) =>
      Vector3(x - other.x, y - other.y, z - other.z);

  Vector3 operator *(double scalar) =>
      Vector3(x * scalar, y * scalar, z * scalar);

  double dot(Vector3 other) => x * other.x + y * other.y + z * other.z;

  /// Unit vector, or null when there is no direction to speak of.
  Vector3? get normalized {
    final m = magnitude;
    if (m < 1e-9) return null;
    return Vector3(x / m, y / m, z / m);
  }

  @override
  String toString() =>
      'Vector3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// Estimates vehicle speed between GPS fixes by integrating longitudinal
/// acceleration.
///
/// Replaces an implementation that was wrong in three separate ways: it
/// estimated gravity as the measured acceleration vector rescaled to 9.81 (so
/// "linear acceleration" reduced to `a·(1 − g/|a|)` and never isolated gravity
/// at all), it took `-y` as the forward axis — hard-coding one phone
/// orientation — and it integrated forever with no correction, so the estimate
/// drifted without bound.
///
/// What this does instead:
///
/// * **Gravity** comes from a slow low-pass of the raw accelerometer, giving a
///   direction rather than a magnitude. The caller supplies user acceleration
///   separately, already gravity-compensated by the platform.
/// * **The forward axis is learned, not assumed.** Over a GPS interval the mean
///   horizontal acceleration must point along the direction of travel, with a
///   sign set by whether the vehicle sped up or slowed down. That gives a
///   candidate axis on every fix, blended into the running estimate.
/// * **The integrator is zeroed against every GPS fix**, so drift is bounded by
///   the fix interval instead of by the length of the trip.
///
/// Until the forward axis is known the estimator does not integrate at all — it
/// holds the last GPS speed. An unknown orientation is reported as such rather
/// than guessed.
class DeadReckoningEstimator {
  /// Gravity is quasi-static; a ~1 s time constant tracks the phone being
  /// re-seated without following vehicle acceleration.
  static const double gravityAlpha = 0.02;

  /// Below this the acceleration is indistinguishable from sensor noise and
  /// road vibration, so it carries no usable direction information.
  static const double minLearnAccelMps2 = 0.4;

  /// How fast the forward axis follows new evidence. Low enough that one noisy
  /// interval cannot swing it, high enough to converge over a few fixes.
  static const double axisBlend = 0.3;

  /// Speeds beyond this are not a car.
  static const double maxSpeedMps = 90;

  Vector3? _gravity;
  Vector3? _forwardAxis;

  double _speedMps = 0;
  double _lastForwardAccel = 0;

  // Mean horizontal acceleration since the last GPS fix, used to learn the axis.
  Vector3 _horizontalSum = Vector3.zero;
  int _horizontalCount = 0;
  double _elapsedSinceZero = 0;

  double? _lastGpsSpeedMps;

  double get speedEstimateMps => _speedMps;
  double get lastForwardAccelMps2 => _lastForwardAccel;

  /// Whether the device→vehicle orientation has been established. While false,
  /// [speedEstimateMps] is simply the last GPS speed.
  bool get orientationKnown => _forwardAxis != null;

  bool get gravityKnown => _gravity != null;

  /// Unit vector along the vehicle's direction of travel, in device axes.
  Vector3? get forwardAxis => _forwardAxis;

  /// Seconds of integration since the last GPS correction. Callers can use this
  /// to decide how far to trust [speedEstimateMps].
  double get secondsSinceGpsFix => _elapsedSinceZero;

  /// Raw accelerometer sample, gravity included. Only its direction is used.
  void addRawAccel(Vector3 raw) {
    if (raw.magnitude < 1e-6) return;
    final current = _gravity;
    _gravity = current == null
        ? raw
        : current + (raw - current) * gravityAlpha;
  }

  /// Platform-provided user acceleration — gravity already removed — over [dt]
  /// seconds.
  void addUserAccel(Vector3 userAccel, double dt) {
    if (dt <= 0 || dt > 1.0) return;

    final horizontal = _horizontalComponent(userAccel);
    if (horizontal == null) return;

    _horizontalSum = _horizontalSum + horizontal * dt;
    _horizontalCount++;
    _elapsedSinceZero += dt;

    final axis = _forwardAxis;
    if (axis == null) {
      // Orientation unknown: hold the last GPS speed rather than integrating
      // along an axis we have not established.
      _lastForwardAccel = 0;
      return;
    }

    _lastForwardAccel = horizontal.dot(axis);
    _speedMps = (_speedMps + _lastForwardAccel * dt).clamp(0.0, maxSpeedMps);
  }

  /// Applies a GPS fix: corrects the integrator and, when the vehicle's speed
  /// changed enough to be informative, refines the forward axis.
  void zeroAgainstGps(double gpsSpeedMps) {
    final previous = _lastGpsSpeedMps;
    final span = _elapsedSinceZero;

    if (previous != null && span > 0 && _horizontalCount > 0) {
      final requiredAccel = (gpsSpeedMps - previous) / span;
      // Time-weighted mean horizontal acceleration over the interval.
      final meanHorizontal = _horizontalSum * (1 / span);

      if (requiredAccel.abs() >= minLearnAccelMps2 &&
          meanHorizontal.magnitude >= minLearnAccelMps2) {
        // Over the interval the mean horizontal acceleration is the forward
        // axis scaled by the longitudinal acceleration, so its direction gives
        // the axis and the sign of that acceleration orients it.
        final direction = meanHorizontal.normalized;
        if (direction != null) {
          final candidate = requiredAccel >= 0 ? direction : direction * -1;
          _forwardAxis = _blendAxis(_forwardAxis, candidate);
        }
      }
    }

    _speedMps = gpsSpeedMps.clamp(0.0, maxSpeedMps);
    _lastGpsSpeedMps = gpsSpeedMps;
    _horizontalSum = Vector3.zero;
    _horizontalCount = 0;
    _elapsedSinceZero = 0;
  }

  /// Forgets everything learned. Called when sensors stop, since the phone may
  /// be in a completely different pose by the next trip.
  void reset() {
    _gravity = null;
    _forwardAxis = null;
    _speedMps = 0;
    _lastForwardAccel = 0;
    _horizontalSum = Vector3.zero;
    _horizontalCount = 0;
    _elapsedSinceZero = 0;
    _lastGpsSpeedMps = null;
  }

  /// The part of [accel] perpendicular to gravity — i.e. in the road plane.
  /// Null until gravity has been established.
  Vector3? _horizontalComponent(Vector3 accel) {
    final gravityDirection = _gravity?.normalized;
    if (gravityDirection == null) return null;
    return accel - gravityDirection * accel.dot(gravityDirection);
  }

  Vector3 _blendAxis(Vector3? current, Vector3 candidate) {
    if (current == null) return candidate;
    final blended = current * (1 - axisBlend) + candidate * axisBlend;
    return blended.normalized ?? candidate;
  }
}
