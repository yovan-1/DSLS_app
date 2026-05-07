import 'dart:math';
import 'speed_calculator.dart';

class RoadSegment {
  final String id;
  final String name;
  final List<MapPoint> waypoints;
  final int speedLimit;
  final int widthMeters;
  final LocationType type;

  const RoadSegment({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.speedLimit,
    this.widthMeters = 20,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'waypoints': waypoints.map((p) => p.toJson()).toList(),
        'speedLimit': speedLimit,
        'widthMeters': widthMeters,
        'type': type.index,
      };

  factory RoadSegment.fromJson(Map<String, dynamic> json) => RoadSegment(
        id: json['id'] as String,
        name: json['name'] as String,
        waypoints: (json['waypoints'] as List)
            .map((p) => MapPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        speedLimit: json['speedLimit'] as int,
        widthMeters: json['widthMeters'] as int? ?? 20,
        type: LocationType.values[json['type'] as int],
      );

  double distanceToPoint(double lat, double lon) {
    if (waypoints.length < 2) {
      if (waypoints.isEmpty) return double.infinity;
      return LocationUtils.haversineDistance(
        lat,
        lon,
        waypoints[0].latitude,
        waypoints[0].longitude,
      );
    }

    double minDistance = double.infinity;
    for (int i = 0; i < waypoints.length - 1; i++) {
      final dist = LocationUtils.pointToLineSegmentDistance(
        lat,
        lon,
        waypoints[i].latitude,
        waypoints[i].longitude,
        waypoints[i + 1].latitude,
        waypoints[i + 1].longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
      }
    }
    return minDistance;
  }

  bool isOnRoad(double lat, double lon) {
    return distanceToPoint(lat, lon) <= widthMeters;
  }
}

class MapPoint {
  final double latitude;
  final double longitude;

  const MapPoint({
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory MapPoint.fromJson(Map<String, dynamic> json) => MapPoint(
        latitude: json['latitude'] as double,
        longitude: json['longitude'] as double,
      );
}

class LocationUtils {
  static const double earthRadius = 6371000;

  static double haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final lat1Rad = _toRadians(lat1);
    final lat2Rad = _toRadians(lat2);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  static double pointToLineSegmentDistance(
      double px, double py, double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final lengthSq = dx * dx + dy * dy;

    if (lengthSq == 0) {
      return haversineDistance(px, py, x1, y1);
    }

    final t = ((px - x1) * dx + (py - y1) * dy) / lengthSq;
    final clampedT = t.clamp(0.0, 1.0);

    final projX = x1 + clampedT * dx;
    final projY = y1 + clampedT * dy;

    return haversineDistance(px, py, projX, projY);
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}