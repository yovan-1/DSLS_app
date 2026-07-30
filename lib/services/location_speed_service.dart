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

class _SpatialGrid {
  static const double _cellSizeDegrees = 0.009;
  final Map<String, List<SpeedZone>> _cells = {};
  List<SpeedZone> _allZones = [];

  void buildIndex(List<SpeedZone> zones) {
    _cells.clear();
    _allZones = List.from(zones);

    for (final zone in zones) {
      final key = _getCellKey(zone.latitude, zone.longitude);
      _cells.putIfAbsent(key, () => []).add(zone);

      for (final neighborKey in _getNeighborKeys(zone.latitude, zone.longitude)) {
        _cells.putIfAbsent(neighborKey, () => []);
      }
    }
  }

  List<SpeedZone> getZonesNear(double lat, double lon) {
    final centerKey = _getCellKey(lat, lon);
    final Set<SpeedZone> nearby = {};

    nearby.addAll(_cells[centerKey] ?? []);

    for (final key in _getNeighborKeys(lat, lon)) {
      nearby.addAll(_cells[key] ?? []);
    }

    if (nearby.isEmpty) {
      return _allZones;
    }

    return nearby.toList();
  }

  String _getCellKey(double lat, double lon) {
    final latCell = (lat / _cellSizeDegrees).floor();
    final lonCell = (lon / _cellSizeDegrees).floor();
    return '$latCell,$lonCell';
  }

  List<String> _getNeighborKeys(double lat, double lon) {
    final latCell = (lat / _cellSizeDegrees).floor();
    final lonCell = (lon / _cellSizeDegrees).floor();

    return [
      '${latCell - 1},${lonCell - 1}',
      '${latCell - 1},$lonCell',
      '${latCell - 1},${lonCell + 1}',
      '$latCell,${lonCell - 1}',
      '$latCell,${lonCell + 1}',
      '${latCell + 1},${lonCell - 1}',
      '${latCell + 1},$lonCell',
      '${latCell + 1},${lonCell + 1}',
    ];
  }
}

class LocationSpeedService extends ChangeNotifier {
  final List<SpeedZone> _zones = [];
  final List<RoadSegment> _roads = [];
  final _SpatialGrid _spatialGrid = _SpatialGrid();

  LocationSpeedResult _currentResult = LocationSpeedResult.defaultResult;
  double? _currentLat;
  double? _currentLon;
  bool _isInitialized = false;

  LocationSpeedResult get currentResult => _currentResult;
  double? get currentLat => _currentLat;
  double? get currentLon => _currentLon;
  bool get isInitialized => _isInitialized;
  LocationSpeedStatus get status => _currentResult.status;

  void initialize(List<SpeedZone> zones, List<RoadSegment> roads) {
    _zones.clear();
    _zones.addAll(zones);
    _roads.clear();
    _roads.addAll(roads);
    _spatialGrid.buildIndex(zones);
    _isInitialized = true;
    notifyListeners();
  }

  void updatePosition(double lat, double lon) {
    _currentLat = lat;
    _currentLon = lon;
    _calculateActiveLocation();
    notifyListeners();
  }

  void _calculateActiveLocation() {
    if (_currentLat == null || _currentLon == null) {
      _currentResult = LocationSpeedResult.defaultResult;
      return;
    }

    final lat = _currentLat!;
    final lon = _currentLon!;

    final nearbyZones = _spatialGrid.getZonesNear(lat, lon);

    for (final zone in nearbyZones) {
      final distance = LocationUtils.haversineDistance(
        lat,
        lon,
        zone.latitude,
        zone.longitude,
      );

      if (distance <= zone.triggerRadius) {
        _currentResult = LocationSpeedResult(
          locationType: zone.type,
          speedLimit: zone.speedLimit,
          activeZoneName: zone.name,
          activeRoadName: '',
          status: LocationSpeedStatus.inZone,
        );
        return;
      }

      if (distance <= zone.triggerRadius * 2) {
        _currentResult = LocationSpeedResult(
          locationType: zone.type,
          speedLimit: zone.speedLimit,
          activeZoneName: '${zone.name} (approaching)',
          activeRoadName: '',
          status: LocationSpeedStatus.approachingZone,
        );
        return;
      }
    }

    for (final road in _roads) {
      if (road.isOnRoad(lat, lon)) {
        _currentResult = LocationSpeedResult(
          locationType: road.type,
          speedLimit: road.speedLimit,
          activeZoneName: '',
          activeRoadName: road.name,
          status: LocationSpeedStatus.onRoad,
        );
        return;
      }
    }

    _currentResult = LocationSpeedResult.defaultResult;
  }

  void reset() {
    _currentLat = null;
    _currentLon = null;
    _currentResult = LocationSpeedResult.defaultResult;
    notifyListeners();
  }
}