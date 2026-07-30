import 'dart:math' as math;

import '../speed_calculator.dart' show WeatherCondition;

/// The state of the road surface, which is what actually determines available
/// grip. Weather is only a proxy for it.
enum SurfaceState {
  dry,
  wet,
  standingWater,
  snow,
  ice,
}

/// Maps weather to an effective deceleration coefficient.
///
/// ## These are design values, not peak tyre grip
///
/// A car with ABS on dry asphalt can brake at roughly 0.7–0.8 g. AASHTO's
/// stopping-sight-distance model deliberately does **not** use that number: it
/// specifies a deceleration of **3.4 m/s² (≈ 0.35 g)**, the rate a driver can
/// sustain while keeping steering control and staying within their comfort
/// envelope. Designing to peak grip would assume every driver performs a
/// textbook emergency stop, which is exactly the assumption a safety product
/// must not make.
///
/// So the values below are `a / g` for the design deceleration on each surface,
/// scaled from the dry reference in proportion to available tyre–road friction.
///
/// Reference: AASHTO Green Book Ch. 3 (deceleration 3.4 m/s²); ITE *Traffic
/// Engineering Handbook* for surface friction ratios.
class FrictionModel {
  const FrictionModel._();

  /// AASHTO design deceleration, m/s².
  static const double designDecelerationMps2 = 3.4;

  /// Design deceleration on dry asphalt, expressed as a fraction of g.
  /// Used as the reference when scaling a posted limit, since posted limits
  /// are set for dry conditions.
  static const double dryFriction = designDecelerationMps2 / 9.81; // ≈ 0.347

  static const Map<SurfaceState, double> _frictionBySurface = {
    SurfaceState.dry: dryFriction,
    SurfaceState.wet: 0.25,
    SurfaceState.standingWater: 0.20,
    SurfaceState.snow: 0.15,
    SurfaceState.ice: 0.08,
  };

  /// Infers the likely surface state from the current weather.
  static SurfaceState surfaceFor(WeatherCondition weather) {
    switch (weather) {
      case WeatherCondition.clear:
      case WeatherCondition.cloudy:
      case WeatherCondition.smoke:
      case WeatherCondition.dust:
      case WeatherCondition.haze:
      case WeatherCondition.fog:
        // Fog impairs sight, not grip — it is handled by the sight-distance
        // constraint instead. Treating it as a grip problem would double-count.
        return SurfaceState.dry;
      case WeatherCondition.rain:
        return SurfaceState.wet;
      case WeatherCondition.heavyRain:
      case WeatherCondition.storm:
        return SurfaceState.standingWater;
      case WeatherCondition.snow:
      case WeatherCondition.sleet:
        return SurfaceState.snow;
      case WeatherCondition.freezingRain:
      case WeatherCondition.hail:
        return SurfaceState.ice;
    }
  }

  /// The coefficient of friction for a surface state.
  static double frictionFor(SurfaceState surface) =>
      _frictionBySurface[surface] ?? dryFriction;

  /// Convenience: weather straight through to a friction coefficient.
  static double frictionForWeather(WeatherCondition weather) =>
      frictionFor(surfaceFor(weather));

  /// How much a posted limit should be scaled back for reduced grip.
  ///
  /// Posted limits are set assuming a dry road. For a fixed geometry the safe
  /// speed scales with the square root of available friction (both braking
  /// distance and cornering force go as v²/f), so the ratio is
  /// `sqrt(f / f_dry)`.
  ///
  /// This yields roughly 0.76 on a wet road, 0.65 in standing water, 0.53 on
  /// snow and 0.38 on ice — consistent with the familiar guidance to halve your
  /// speed on snow and ice.
  static double gripFactor(SurfaceState surface) {
    final f = frictionFor(surface);
    return math.sqrt(f / dryFriction);
  }

  static String label(SurfaceState surface) {
    switch (surface) {
      case SurfaceState.dry:
        return 'Dry';
      case SurfaceState.wet:
        return 'Wet';
      case SurfaceState.standingWater:
        return 'Standing water';
      case SurfaceState.snow:
        return 'Snow';
      case SurfaceState.ice:
        return 'Ice';
    }
  }
}
