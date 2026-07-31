import 'package:flutter/foundation.dart';
import '../models/speed_zone.dart';
import '../models/road_segment.dart' show RoadSegment, LocationUtils;
import '../models/speed_calculator.dart';
import '../models/speed_model/road_conditions.dart' show LimitSource;

enum LocationSpeedStatus {
  none,
  onRoad,
  approachingZone,
  inZone,
}

class LocationSpeedResult {
  final LocationType locationType;
  final int speedLimit;
  final String activeZoneName;
  final String activeRoadName;
  final LocationSpeedStatus status;

  /// Whether [speedLimit] is a real limit for this place or a fallback guess.
  ///
  /// The speed model applies an uncertainty margin only to inferred limits;
  /// curated ones already account for their surroundings.
  final LimitSource limitSource;

  const LocationSpeedResult({
    required this.locationType,
    required this.speedLimit,
    required this.activeZoneName,
    required this.activeRoadName,
    required this.status,
    this.limitSource = LimitSource.curated,
  });

  /// Used when the driver is outside every mapped zone and road. The 60 km/h is
  /// a guess, and [limitSource] says so.
  static const LocationSpeedResult defaultResult = LocationSpeedResult(
    locationType: LocationType.urban,
    speedLimit: 60,
    activeZoneName: '',
    activeRoadName: '',
    status: LocationSpeedStatus.none,
    limitSource: LimitSource.inferred,
  );
}

/// A zone plus how far away it is, so selection can compare candidates.
class _ZoneMatch {
  final SpeedZone zone;
  final double distance;

  const _ZoneMatch(this.zone, this.distance);
}

class LocationSpeedService extends ChangeNotifier {
  final List<SpeedZone> _zones = [];
  final List<RoadSegment> _roads = [];

  LocationSpeedResult _currentResult = LocationSpeedResult.defaultResult;
  double? _currentLat;
  double? _currentLon;
  bool _isInitialized = false;

  LocationSpeedResult get currentResult => _currentResult;
  double? get currentLat => _currentLat;
  double? get currentLon => _currentLon;
  bool get isInitialized => _isInitialized;
  LocationSpeedStatus get status => _currentResult.status;

  /// How much warning an approach alert should give, in seconds.
  ///
  /// The approach ring used to be a flat `2 × triggerRadius`, which meant the
  /// warning time depended on the size of the zone rather than on how fast the
  /// driver was closing on it — the 10 m radius around a car park gave under a
  /// second of notice at highway speed. Scaling with speed gives a constant
  /// lead time instead.
  static const double approachLeadSeconds = 8;

  /// Consecutive agreeing fixes before the active road is allowed to change.
  ///
  /// A single noisy fix at a junction should not swing the speed ceiling
  /// mid-corner. Applied to roads only: zones are safety-critical and must
  /// engage on the first fix that enters them.
  static const int roadSwitchFixes = 3;

  String? _candidateRoadId;
  int _candidateRoadFixes = 0;
  String? _activeRoadId;

  void initialize(List<SpeedZone> zones, List<RoadSegment> roads) {
    _zones.clear();
    _zones.addAll(zones);
    _roads.clear();
    _roads.addAll(roads);
    _isInitialized = true;
    notifyListeners();
  }

  /// [speedKph] scales the approach ring; without it an approach alert can only
  /// fire once the driver is already inside the zone.
  void updatePosition(double lat, double lon, {double speedKph = 0}) {
    _previousLat = _currentLat;
    _previousLon = _currentLon;
    _currentLat = lat;
    _currentLon = lon;
    _calculateActiveLocation(speedKph);
    notifyListeners();
  }

  double? _previousLat;
  double? _previousLon;

  void _calculateActiveLocation(double speedKph) {
    final lat = _currentLat;
    final lon = _currentLon;
    if (lat == null || lon == null) {
      _currentResult = LocationSpeedResult.defaultResult;
      return;
    }

    final inside = _nearestZoneWithin(lat, lon, (z, d) => d <= z.triggerRadius);
    if (inside != null) {
      _currentResult = LocationSpeedResult(
        locationType: inside.zone.type,
        speedLimit: inside.zone.speedLimit,
        activeZoneName: inside.zone.name,
        activeRoadName: '',
        status: LocationSpeedStatus.inZone,
      );
      return;
    }

    final approaching = _nearestApproachingZone(lat, lon, speedKph);
    if (approaching != null) {
      _currentResult = LocationSpeedResult(
        locationType: approaching.zone.type,
        speedLimit: approaching.zone.speedLimit,
        activeZoneName: '${approaching.zone.name} (approaching)',
        activeRoadName: '',
        status: LocationSpeedStatus.approachingZone,
      );
      return;
    }

    final road = _nearestRoad(lat, lon);
    if (road != null) {
      _currentResult = LocationSpeedResult(
        locationType: road.type,
        speedLimit: road.speedLimit,
        activeZoneName: '',
        activeRoadName: road.name,
        status: LocationSpeedStatus.onRoad,
        limitSource: road.limitSource,
      );
      return;
    }

    _currentResult = LocationSpeedResult.defaultResult;
  }

  /// Nearest zone satisfying [test], with ties broken toward the stricter
  /// limit and then by id.
  ///
  /// The original returned the *first* zone that qualified, out of a `Set`
  /// whose iteration order was identity-hash based — so overlapping zones
  /// resolved arbitrarily, and the same coordinate could yield different speed
  /// limits between runs. Selection is now total and deterministic.
  _ZoneMatch? _nearestZoneWithin(
    double lat,
    double lon,
    bool Function(SpeedZone zone, double distance) test,
  ) {
    _ZoneMatch? best;
    for (final zone in _zones) {
      final distance = LocationUtils.haversineDistance(
        lat,
        lon,
        zone.latitude,
        zone.longitude,
      );
      if (!test(zone, distance)) continue;
      if (best == null || _isBetterZone(zone, distance, best)) {
        best = _ZoneMatch(zone, distance);
      }
    }
    return best;
  }

  bool _isBetterZone(SpeedZone zone, double distance, _ZoneMatch best) {
    // Nearest wins. Where two zones are effectively equidistant, take the
    // lower limit — being wrong in the cautious direction is the cheaper error
    // for a speed advisory.
    const epsilonMetres = 1.0;
    final delta = distance - best.distance;
    if (delta < -epsilonMetres) return true;
    if (delta > epsilonMetres) return false;
    if (zone.speedLimit != best.zone.speedLimit) {
      return zone.speedLimit < best.zone.speedLimit;
    }
    return zone.id.compareTo(best.zone.id) < 0;
  }

  /// A zone is "approaching" only when the driver is actually closing on it.
  ///
  /// The old distance-only test fired on the way *out* of a zone as well as on
  /// the way in, so leaving a school zone raised a fresh approach alert.
  _ZoneMatch? _nearestApproachingZone(double lat, double lon, double speedKph) {
    final previousLat = _previousLat;
    final previousLon = _previousLon;
    if (previousLat == null || previousLon == null) return null;

    final speedMps = speedKph / 3.6;

    return _nearestZoneWithin(lat, lon, (zone, distance) {
      final ring = zone.triggerRadius + speedMps * approachLeadSeconds;
      if (distance > ring) return false;

      final previousDistance = LocationUtils.haversineDistance(
        previousLat,
        previousLon,
        zone.latitude,
        zone.longitude,
      );
      return distance < previousDistance;
    });
  }

  /// Nearest road within its own corridor, with hysteresis on switching.
  RoadSegment? _nearestRoad(double lat, double lon) {
    RoadSegment? best;
    double bestDistance = double.infinity;

    for (final road in _roads) {
      final distance = road.distanceToPoint(lat, lon);
      if (distance > road.widthMeters) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = road;
      }
    }

    if (best == null) {
      _candidateRoadId = null;
      _candidateRoadFixes = 0;
      _activeRoadId = null;
      return null;
    }

    if (best.id == _activeRoadId) {
      _candidateRoadId = null;
      _candidateRoadFixes = 0;
      return best;
    }

    if (best.id == _candidateRoadId) {
      _candidateRoadFixes++;
    } else {
      _candidateRoadId = best.id;
      _candidateRoadFixes = 1;
    }

    if (_activeRoadId == null || _candidateRoadFixes >= roadSwitchFixes) {
      _activeRoadId = best.id;
      _candidateRoadId = null;
      _candidateRoadFixes = 0;
      return best;
    }

    // Not yet convinced: hold the previous road rather than flapping.
    return _roads.where((r) => r.id == _activeRoadId).firstOrNull ?? best;
  }

  void reset() {
    _currentLat = null;
    _currentLon = null;
    _previousLat = null;
    _previousLon = null;
    _candidateRoadId = null;
    _candidateRoadFixes = 0;
    _activeRoadId = null;
    _currentResult = LocationSpeedResult.defaultResult;
    notifyListeners();
  }
}