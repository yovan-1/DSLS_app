import 'dart:math';
import 'speed_calculator.dart';
import 'speed_model/road_conditions.dart' show LimitSource;

class RoadSegment {
  final String id;
  final String name;
  final List<MapPoint> waypoints;
  final int speedLimit;
  final int widthMeters;
  final LocationType type;

  /// Whether [speedLimit] is a real posted limit or a guess.
  ///
  /// Defaults to [LimitSource.inferred], because the segments shipped in
  /// `lib/data/roads.dart` are eyeballed polylines with no provenance — one of
  /// them approximates ~90 km of highway with four points. They used to reach
  /// [SpeedAdvisor] as `curated`, which is full confidence with no uncertainty
  /// margin. OSM-derived rows set this from the `maxspeed` tag instead.
  final LimitSource limitSource;

  const RoadSegment({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.speedLimit,
    this.widthMeters = 20,
    required this.type,
    this.limitSource = LimitSource.inferred,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'waypoints': waypoints.map((p) => p.toJson()).toList(),
        'speedLimit': speedLimit,
        'widthMeters': widthMeters,
        // By name, not index — see the note on SpeedZone.toJson.
        'type': type.name,
        'limitSource': limitSource.name,
      };

  factory RoadSegment.fromJson(Map<String, dynamic> json) => RoadSegment(
        id: json['id'] as String,
        name: json['name'] as String,
        waypoints: (json['waypoints'] as List)
            .map((p) => MapPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        speedLimit: json['speedLimit'] as int,
        widthMeters: json['widthMeters'] as int? ?? 20,
        type: _locationTypeFrom(json['type']),
        limitSource: LimitSource.values.firstWhere(
          (v) => v.name == json['limitSource'],
          orElse: () => LimitSource.inferred,
        ),
      );

  /// Accepts both the current name form and the legacy index form.
  static LocationType _locationTypeFrom(Object? raw) {
    if (raw is int) {
      return raw >= 0 && raw < LocationType.values.length
          ? LocationType.values[raw]
          : LocationType.urban;
    }
    return LocationType.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => LocationType.urban,
    );
  }

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

  /// Shortest distance in metres from a point to a segment, both given as
  /// (latitude, longitude) in degrees.
  ///
  /// The projection is computed in a local equirectangular frame — longitude
  /// degrees scaled by `cos(latitude)` — rather than in raw degree space. A
  /// degree of longitude is only as long as a degree of latitude at the
  /// equator; at 50°N it is about two thirds as long. Projecting in raw degrees
  /// therefore lands the nearest point in the wrong place, by more the further
  /// you get from the equator and the longer the segment. That is invisible at
  /// Mbarara (0.6°S, cos ≈ 0.99995) and wrong everywhere else, so it stayed
  /// latent while the only data was eight hand-typed Mbarara zones.
  static double pointToLineSegmentDistance(
      double px, double py, double lat1, double lon1, double lat2, double lon2) {
    // Scale longitude at the segment's mid-latitude. Over a single road
    // segment the change in cos(lat) is negligible, so one factor is enough.
    final lonScale = cos(_toRadians((lat1 + lat2) / 2));

    final dLat = lat2 - lat1;
    final dLon = (lon2 - lon1) * lonScale;
    final lengthSq = dLat * dLat + dLon * dLon;

    if (lengthSq == 0) {
      return haversineDistance(px, py, lat1, lon1);
    }

    final t = ((px - lat1) * dLat + ((py - lon1) * lonScale) * dLon) / lengthSq;
    final clampedT = t.clamp(0.0, 1.0);

    // Back out of the scaled frame to get real coordinates for the haversine.
    final projLat = lat1 + clampedT * dLat;
    final projLon = lon1 + clampedT * (lon2 - lon1);

    return haversineDistance(px, py, projLat, projLon);
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}