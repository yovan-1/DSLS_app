import 'dart:math' as math;

import '../speed_calculator.dart' show WeatherCondition, VisibilityLevel;
import 'solar_position.dart';

/// What limits how far ahead the driver can see.
enum SightLimiter {
  /// Nothing meaningfully restricts sight.
  unrestricted,

  /// Darkness — sight distance is bounded by headlight throw.
  headlights,

  /// Weather (fog, heavy rain, smoke, dust).
  weather,

  /// The camera measured less light than weather and time alone imply.
  measuredLight,
}

/// The available sight distance, in metres, plus what caused it.
class SightDistance {
  final double metres;
  final SightLimiter limiter;

  const SightDistance({required this.metres, required this.limiter});
}

/// Derives available sight distance from darkness, weather and (optionally) the
/// camera's ambient-light reading.
///
/// Every number here answers a physical question — "how far ahead can the
/// driver actually see?" — rather than being a tuned percentage.
class SightDistanceModel {
  const SightDistanceModel._();

  /// Sight distance treated as effectively unrestricted. Large enough that the
  /// stopping-distance constraint never binds below the posted limit.
  static const double unrestrictedMetres = 1000;

  /// Typical low-beam headlight throw, metres — the sight distance on an
  /// **unlit** road at night.
  ///
  /// This is the single most under-modelled hazard in night driving: low beams
  /// illuminate about 60 m, which does not support motorway speeds. Drivers
  /// routinely overdrive their headlights without realising it.
  static const double lowBeamMetres = 60;

  /// Sight distance on a **lit** road at night.
  ///
  /// Street lighting, delineation and other vehicles' lights give far more
  /// preview than headlights alone, which is why lit motorways carry the same
  /// limit at night as by day.
  static const double litRoadNightMetres = 250;

  /// Used when we do not yet know whether the road is lit.
  ///
  /// A deliberate compromise. Assuming unlit everywhere would have the app
  /// demanding ~48 km/h on a lit dual carriageway, and an advisory drivers
  /// learn to ignore protects nobody. Assuming lit everywhere would miss the
  /// genuine hazard on an unlit rural road. Replace this with the real OSM
  /// `lit` tag once the road database lands.
  static const double unknownLightingNightMetres = 150;

  /// Ambient light at civil twilight still gives considerably more than
  /// headlights alone.
  static const double twilightMetres = 250;

  /// Low sun in the driver's eyes cuts effective sight sharply.
  static const double lowSunGlareMetres = 200;

  /// Sight distance caps imposed by weather, in metres.
  static const Map<WeatherCondition, double> _weatherCapMetres = {
    WeatherCondition.fog: 50,
    WeatherCondition.smoke: 80,
    WeatherCondition.dust: 80,
    WeatherCondition.heavyRain: 100,
    WeatherCondition.storm: 100,
    WeatherCondition.hail: 100,
    WeatherCondition.snow: 120,
    WeatherCondition.sleet: 150,
    WeatherCondition.haze: 200,
    WeatherCondition.freezingRain: 200,
    WeatherCondition.rain: 300,
  };

  /// Caps implied by the camera's ambient-brightness reading.
  ///
  /// The camera is treated as a corroborating signal only: it can lower the
  /// sight distance but never raise it. A phone in a pocket reads "very poor"
  /// regardless of conditions, so it must never be the sole authority.
  static const Map<VisibilityLevel, double> _cameraCapMetres = {
    VisibilityLevel.excellent: unrestrictedMetres,
    VisibilityLevel.good: 400,
    VisibilityLevel.moderate: 200,
    VisibilityLevel.poor: 120,
    VisibilityLevel.veryPoor: 60,
  };

  /// Computes the binding sight distance.
  ///
  /// [cameraVisibility] may be null when the camera is unavailable (app
  /// backgrounded, permission denied, phone pocketed), in which case daylight
  /// and weather alone decide.
  static SightDistance compute({
    required DaylightState daylight,
    required WeatherCondition weather,
    VisibilityLevel? cameraVisibility,
    bool? isLit,
  }) {
    var metres = unrestrictedMetres;
    var limiter = SightLimiter.unrestricted;

    final daylightMetres = _daylightCap(daylight, isLit);
    if (daylightMetres < metres) {
      metres = daylightMetres;
      limiter = SightLimiter.headlights;
    }

    final weatherMetres = _weatherCapMetres[weather] ?? unrestrictedMetres;
    if (weatherMetres < metres) {
      metres = weatherMetres;
      limiter = SightLimiter.weather;
    }

    if (cameraVisibility != null) {
      final cameraMetres =
          _cameraCapMetres[cameraVisibility] ?? unrestrictedMetres;
      if (cameraMetres < metres) {
        metres = cameraMetres;
        limiter = SightLimiter.measuredLight;
      }
    }

    return SightDistance(metres: math.max(metres, 10), limiter: limiter);
  }

  static double _daylightCap(DaylightState daylight, bool? isLit) {
    switch (daylight) {
      case DaylightState.daylight:
        return unrestrictedMetres;
      case DaylightState.lowSun:
        return lowSunGlareMetres;
      case DaylightState.twilight:
        return twilightMetres;
      case DaylightState.night:
        if (isLit == true) return litRoadNightMetres;
        if (isLit == false) return lowBeamMetres;
        return unknownLightingNightMetres;
    }
  }
}
