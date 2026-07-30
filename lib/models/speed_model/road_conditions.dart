import '../speed_calculator.dart' show LocationType, VisibilityLevel, WeatherCondition;
import 'solar_position.dart';

/// Where the speed ceiling came from.
///
/// This distinction is what stops the model double-counting location. When a
/// limit is [posted] or [curated] it already encodes the surroundings — a 30
/// km/h school-zone sign is a school-zone-aware number — so applying a further
/// "school zone" reduction on top of it is wrong. The previous model did
/// exactly that, taking a 30 km/h zone down to 9 km/h before a floor rescued it.
enum LimitSource {
  /// A real posted limit (OSM `maxspeed`, or a sign we trust).
  posted,

  /// Hand-curated by the project for a known location.
  curated,

  /// Guessed from road class or a fallback default — treat with caution.
  inferred,
}

/// Everything the speed model needs to know about where the driver is and what
/// the conditions are.
class RoadConditions {
  /// The speed ceiling in km/h. The model never recommends above this.
  final int speedLimitKph;

  /// Whether [speedLimitKph] is trustworthy.
  final LimitSource limitSource;

  /// The kind of road/area, used for advisories and — only when the limit is
  /// [LimitSource.inferred] — for an uncertainty margin.
  final LocationType roadClass;

  final WeatherCondition weather;

  final DaylightState daylight;

  /// Camera-derived ambient light, or null when the camera is unavailable.
  final VisibilityLevel? cameraVisibility;

  /// Whether the road has street lighting. Null means unknown, which is the
  /// case until the OSM `lit` tag is available. This materially changes the
  /// night-time recommendation — see [SightDistanceModel].
  final bool? isLit;

  /// Road grade (uphill positive). Reserved for when elevation data lands;
  /// currently always 0.
  final double grade;

  const RoadConditions({
    required this.speedLimitKph,
    required this.limitSource,
    required this.roadClass,
    required this.weather,
    required this.daylight,
    this.cameraVisibility,
    this.isLit,
    this.grade = 0,
  });

  RoadConditions copyWith({
    int? speedLimitKph,
    LimitSource? limitSource,
    LocationType? roadClass,
    WeatherCondition? weather,
    DaylightState? daylight,
    VisibilityLevel? cameraVisibility,
    bool? isLit,
    double? grade,
  }) {
    return RoadConditions(
      speedLimitKph: speedLimitKph ?? this.speedLimitKph,
      limitSource: limitSource ?? this.limitSource,
      roadClass: roadClass ?? this.roadClass,
      weather: weather ?? this.weather,
      daylight: daylight ?? this.daylight,
      cameraVisibility: cameraVisibility ?? this.cameraVisibility,
      isLit: isLit ?? this.isLit,
      grade: grade ?? this.grade,
    );
  }
}
