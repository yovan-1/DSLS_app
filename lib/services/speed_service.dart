import 'package:flutter/foundation.dart';

import '../data/speed_zones.dart';
import '../models/speed_calculator.dart'
    show VisibilityLevel, WeatherCondition;
import '../models/speed_model/road_conditions.dart';
import '../models/speed_model/solar_position.dart';
import '../models/speed_model/speed_advisor.dart';
import '../models/speed_model/speed_recommendation.dart';
import 'location_speed_service.dart';
import 'road_database.dart';

/// Assembles the inputs the speed model needs and exposes the current
/// recommendation.
///
/// Replaces the old `SpeedParameters` plumbing, which carried a `DayPeriod`
/// clock bucket and a `baseSpeedLimit` that had to be patched by the screen.
/// Location now flows through in one place, carrying its provenance so the
/// model knows whether the limit is real or guessed.
class SpeedService extends ChangeNotifier {
  final LocationSpeedService _locationSpeedService = LocationSpeedService();
  bool _locationServiceInitialized = false;

  bool _isMonitoring = false;
  int _currentSpeed = 0;

  WeatherCondition _weather = WeatherCondition.clear;
  VisibilityLevel? _cameraVisibility;
  DaylightState _daylight = DaylightState.daylight;
  double? _latitude;
  double? _longitude;

  SpeedService() {
    _initializeLocationService();
  }

  bool get isMonitoring => _isMonitoring;
  int get currentSpeed => _currentSpeed;
  LocationSpeedService get locationService => _locationSpeedService;
  bool get locationServiceInitialized => _locationServiceInitialized;
  WeatherCondition get weather => _weather;
  DaylightState get daylight => _daylight;
  VisibilityLevel? get cameraVisibility => _cameraVisibility;

  LocationSpeedResult get locationResult => _locationSpeedService.currentResult;

  bool get isApproachingZone =>
      _locationSpeedService.status == LocationSpeedStatus.approachingZone ||
      _locationSpeedService.status == LocationSpeedStatus.inZone;

  void _initializeLocationService() {
    // Curated zones only. The three hand-typed road segments that used to be
    // passed here are superseded by the OSM database — one of them
    // approximated ~90 km of highway with four waypoints, and none carried any
    // provenance. Curated *zones* stay: they cover specific school gates and
    // hospital entrances that OSM does not tag.
    _locationSpeedService.initialize(mbararaSpeedZones, const []);
    _locationServiceInitialized = true;
  }

  /// The current inputs to the speed model.
  RoadConditions get conditions {
    final location = locationResult;
    return RoadConditions(
      speedLimitKph: location.speedLimit,
      limitSource: location.limitSource,
      roadClass: location.locationType,
      weather: _weather,
      daylight: _daylight,
      cameraVisibility: _cameraVisibility,
      // From the OSM `lit` tag where the way carries one. Only ~0.8% of ways
      // in the shipped extract do, so this is usually still null and the
      // sight-distance model keeps its unknown-lighting fallback.
      isLit: location.isLit,
    );
  }

  /// OSM `surface` for the matched road, when surveyed. ~14.4% of ways in the
  /// extract carry it, and most of those are `unpaved`.
  String? get roadSurface => locationResult.surface;

  /// Identifier of the matched road in the offline database, for the trip
  /// record. Null when the fix is not on a mapped road.
  int? get roadId => locationResult.roadId;

  SpeedRecommendation get recommendation => SpeedAdvisor.evaluate(conditions);

  /// [speedKph] lets the zone matcher size its approach ring by how fast the
  /// driver is closing, rather than by how big the zone happens to be.
  Future<void> updatePosition(
    double lat,
    double lon, {
    double speedKph = 0,
  }) async {
    _latitude = lat;
    _longitude = lon;
    _refreshDaylight();
    notifyListeners();
    await _locationSpeedService.updatePosition(lat, lon, speedKph: speedKph);
    notifyListeners();
  }

  /// Makes the offline road database available to the matcher.
  void attachRoadDatabase(RoadDatabase database) {
    _locationSpeedService.attachRoadDatabase(database);
    notifyListeners();
  }

  /// Recomputes whether it is dark from the sun's actual position.
  ///
  /// Needs a fix first — without a location there is no meaningful answer, so
  /// the previous value is kept rather than guessing from the clock.
  void _refreshDaylight() {
    final lat = _latitude;
    final lon = _longitude;
    if (lat == null || lon == null) return;

    _daylight = SolarPosition.stateFor(
      utc: DateTime.now().toUtc(),
      latitude: lat,
      longitude: lon,
    );
  }

  void updateWeather(WeatherCondition weather) {
    _weather = weather;
    notifyListeners();
  }

  /// Camera-derived ambient light. Pass null when the camera is unavailable so
  /// the model falls back to daylight and weather instead of a stale reading.
  void updateVisibility(VisibilityLevel? visibility) {
    _cameraVisibility = visibility;
    notifyListeners();
  }

  void setMonitoring(bool value) {
    _isMonitoring = value;
    notifyListeners();
  }

  void updateCurrentSpeed(int speed) {
    _currentSpeed = speed;
    notifyListeners();
  }

  void reset() {
    _isMonitoring = false;
    _currentSpeed = 0;
    _weather = WeatherCondition.clear;
    _cameraVisibility = null;
    _daylight = DaylightState.daylight;
    _latitude = null;
    _longitude = null;
    _locationSpeedService.reset();
    notifyListeners();
  }
}
