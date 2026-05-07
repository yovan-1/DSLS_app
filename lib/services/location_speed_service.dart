import 'package:flutter/foundation.dart';
import '../models/speed_zone.dart';
import '../models/road_segment.dart' show RoadSegment, LocationUtils;
import '../models/speed_calculator.dart';

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

  const LocationSpeedResult({
    required this.locationType,
    required this.speedLimit,
    required this.activeZoneName,
    required this.activeRoadName,
    required this.status,
  });

  static const LocationSpeedResult defaultResult = LocationSpeedResult(
    locationType: LocationType.urban,
    speedLimit: 60,
    activeZoneName: '',
    activeRoadName: '',
    status: LocationSpeedStatus.none,
  );
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

  void initialize(List<SpeedZone> zones, List<RoadSegment> roads) {
    _zones.clear();
    _zones.addAll(zones);
    _roads.clear();
    _roads.addAll(roads);
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

    for (final zone in _zones) {
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