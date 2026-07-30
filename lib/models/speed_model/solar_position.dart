import 'dart:math' as math;

/// How much natural light is available, derived from the sun's actual position
/// rather than from clock-hour buckets.
///
/// The old model bucketed the clock into morning/afternoon/evening/night, which
/// is a poor proxy: 19:00 is pitch dark in one place and broad daylight in
/// another, and the boundaries drift across the year. What the speed model
/// actually needs to know is whether the driver is relying on headlights.
enum DaylightState {
  /// Sun well above the horizon.
  daylight,

  /// Sun low (0–6°) — usable light, but direct glare into the driver's eyes.
  lowSun,

  /// Civil twilight: sun between 0 and −6°. Headlights on, some ambient light.
  twilight,

  /// Sun below −6°. Sight distance is limited by headlight throw.
  night,
}

/// Computes solar elevation using the NOAA solar-position approximation.
///
/// Accurate to well within a degree, which is far more precision than the
/// daylight banding needs, and requires no network call or almanac data.
class SolarPosition {
  const SolarPosition._();

  /// Solar elevation above the horizon, in degrees, for a UTC instant.
  static double elevationDegrees({
    required DateTime utc,
    required double latitude,
    required double longitude,
  }) {
    final time = utc.toUtc();
    final dayOfYear = _dayOfYear(time);
    final hourFraction =
        time.hour + time.minute / 60.0 + time.second / 3600.0;

    // Fractional year, radians.
    final gamma = (2 * math.pi / 365.0) *
        (dayOfYear - 1 + (hourFraction - 12) / 24.0);

    // Equation of time, minutes.
    final eqTime = 229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma) -
            0.014615 * math.cos(2 * gamma) -
            0.040849 * math.sin(2 * gamma));

    // Solar declination, radians.
    final decl = 0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2 * gamma) +
        0.000907 * math.sin(2 * gamma) -
        0.002697 * math.cos(3 * gamma) +
        0.00148 * math.sin(3 * gamma);

    // True solar time, minutes. No timezone term is needed because the input
    // is already UTC.
    final trueSolarTime = (hourFraction * 60) + eqTime + (4 * longitude);

    // Hour angle, degrees, then radians.
    var hourAngle = (trueSolarTime / 4) - 180;
    hourAngle = _wrapDegrees(hourAngle);
    final ha = _toRadians(hourAngle);

    final latRad = _toRadians(latitude);
    final cosZenith = (math.sin(latRad) * math.sin(decl)) +
        (math.cos(latRad) * math.cos(decl) * math.cos(ha));
    final zenith = math.acos(cosZenith.clamp(-1.0, 1.0));

    return 90 - _toDegrees(zenith);
  }

  /// Bands the solar elevation into the states the speed model reasons about.
  static DaylightState stateFor({
    required DateTime utc,
    required double latitude,
    required double longitude,
  }) {
    final elevation = elevationDegrees(
      utc: utc,
      latitude: latitude,
      longitude: longitude,
    );
    return stateForElevation(elevation);
  }

  static DaylightState stateForElevation(double elevationDegrees) {
    if (elevationDegrees > 6) return DaylightState.daylight;
    if (elevationDegrees > 0) return DaylightState.lowSun;
    if (elevationDegrees > -6) return DaylightState.twilight;
    return DaylightState.night;
  }

  static int _dayOfYear(DateTime date) =>
      date.difference(DateTime.utc(date.year, 1, 1)).inDays + 1;

  static double _toRadians(double degrees) => degrees * math.pi / 180;
  static double _toDegrees(double radians) => radians * 180 / math.pi;

  /// Normalises an hour angle into (−180, 180].
  static double _wrapDegrees(double degrees) {
    var d = degrees % 360;
    if (d > 180) d -= 360;
    if (d <= -180) d += 360;
    return d;
  }

  static String label(DaylightState state) {
    switch (state) {
      case DaylightState.daylight:
        return 'Daylight';
      case DaylightState.lowSun:
        return 'Low sun';
      case DaylightState.twilight:
        return 'Twilight';
      case DaylightState.night:
        return 'Night';
    }
  }
}
