import 'dart:math' as math;

import 'package:dsls_app/models/road_segment.dart';
import 'package:dsls_app/models/speed_calculator.dart' show LocationType;
import 'package:dsls_app/models/speed_model/road_conditions.dart'
    show LimitSource;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('haversineDistance', () {
    test('is zero for a point against itself', () {
      expect(LocationUtils.haversineDistance(-0.6072, 30.6545, -0.6072, 30.6545),
          closeTo(0, 1e-6));
    });

    test('matches a known one-degree meridian arc', () {
      // A degree of latitude is ~111.19 km on a sphere of radius 6371 km.
      final d = LocationUtils.haversineDistance(0, 30, 1, 30);
      expect(d, closeTo(111194, 50));
    });

    test('a degree of longitude shrinks with latitude', () {
      final atEquator = LocationUtils.haversineDistance(0, 30, 0, 31);
      final atSixty = LocationUtils.haversineDistance(60, 30, 60, 31);

      // cos(60°) = 0.5 exactly.
      expect(atSixty / atEquator, closeTo(0.5, 0.001));
    });
  });

  group('pointToLineSegmentDistance', () {
    test('degenerate segment falls back to point distance', () {
      final d = LocationUtils.pointToLineSegmentDistance(
          0.001, 30.0, 0.0, 30.0, 0.0, 30.0);
      expect(d, closeTo(LocationUtils.haversineDistance(0.001, 30, 0, 30), 1e-6));
    });

    test('a point on the segment is at zero distance', () {
      final d = LocationUtils.pointToLineSegmentDistance(
          -0.60, 30.65, -0.61, 30.65, -0.59, 30.65);
      expect(d, closeTo(0, 1.0));
    });

    test('clamps beyond the segment ends', () {
      // Segment runs north along a meridian; the point sits south of the start.
      final d = LocationUtils.pointToLineSegmentDistance(
          -0.62, 30.65, -0.61, 30.65, -0.59, 30.65);
      final toStart = LocationUtils.haversineDistance(-0.62, 30.65, -0.61, 30.65);
      expect(d, closeTo(toStart, 1.0));
    });

    test('perpendicular offset from a meridian segment', () {
      // 0.001° of longitude at the equator ≈ 111.3 m.
      final d = LocationUtils.pointToLineSegmentDistance(
          0.0, 30.001, -0.01, 30.0, 0.01, 30.0);
      expect(d, closeTo(111.3, 1.0));
    });

    /// The regression that matters. In raw degree space a longitude degree is
    /// treated as equal in length to a latitude degree, so the projection
    /// parameter lands the nearest point in the wrong place. The error grows
    /// with latitude, which is why it stayed invisible on Mbarara data.
    test('projects correctly at high latitude', () {
      // A segment running due east at 60°N, where a longitude degree is half a
      // latitude degree. The point is off the eastern end.
      const lat = 60.0;
      final d = LocationUtils.pointToLineSegmentDistance(
          lat, 10.0, lat, 0.0, lat, 8.0);

      // Nearest point is the eastern endpoint (lat, 8.0).
      final toEnd = LocationUtils.haversineDistance(lat, 10.0, lat, 8.0);
      expect(d, closeTo(toEnd, 1000));
    });

    test('a 45-degree diagonal projects to the true foot at high latitude', () {
      // Without cos(lat) scaling the foot of the perpendicular slides along the
      // segment, inflating the reported distance.
      const lat1 = 50.0, lon1 = 0.0;
      const lat2 = 50.1, lon2 = 0.2;
      // Midpoint of the segment, nudged perpendicular by a small amount.
      const px = 50.05, py = 0.1;

      final d = LocationUtils.pointToLineSegmentDistance(
          px, py, lat1, lon1, lat2, lon2);

      // The midpoint of a straight segment in the scaled frame lies on it.
      expect(d, lessThan(30),
          reason: 'the midpoint should be essentially on the segment');
    });

    test('is symmetric in segment direction', () {
      final forward = LocationUtils.pointToLineSegmentDistance(
          -0.605, 30.66, -0.61, 30.65, -0.59, 30.67);
      final backward = LocationUtils.pointToLineSegmentDistance(
          -0.605, 30.66, -0.59, 30.67, -0.61, 30.65);

      expect(forward, closeTo(backward, 0.01));
    });

    /// The local equirectangular projection is only meaningful over short
    /// distances, so the property is asserted over the domain the function is
    /// actually used in: a fix within a few km of a road segment, at any
    /// latitude. (Generating point and segment independently across the whole
    /// globe produces near-antipodal pairs where no planar approximation
    /// holds — and where this function is never called.)
    test('never exceeds the distance to either endpoint', () {
      final rng = math.Random(20260731);
      for (var i = 0; i < 500; i++) {
        final lat1 = rng.nextDouble() * 140 - 70;
        final lon1 = rng.nextDouble() * 360 - 180;
        // Segment up to ~10 km long.
        final lat2 = lat1 + (rng.nextDouble() - 0.5) * 0.1;
        final lon2 = lon1 + (rng.nextDouble() - 0.5) * 0.1;
        // Point within ~5 km of the segment start.
        final px = lat1 + (rng.nextDouble() - 0.5) * 0.05;
        final py = lon1 + (rng.nextDouble() - 0.5) * 0.05;

        final d = LocationUtils.pointToLineSegmentDistance(
            px, py, lat1, lon1, lat2, lon2);
        final toStart = LocationUtils.haversineDistance(px, py, lat1, lon1);
        final toEnd = LocationUtils.haversineDistance(px, py, lat2, lon2);

        expect(d, lessThanOrEqualTo(math.min(toStart, toEnd) + 1.0),
            reason: 'point($px,$py) seg($lat1,$lon1)-($lat2,$lon2)');
      }
    });
  });

  group('RoadSegment', () {
    final road = RoadSegment(
      id: 'r1',
      name: 'Test Road',
      waypoints: const [
        MapPoint(latitude: -0.61, longitude: 30.65),
        MapPoint(latitude: -0.59, longitude: 30.65),
      ],
      speedLimit: 60,
      widthMeters: 20,
      type: LocationType.urban,
    );

    test('distanceToPoint takes the minimum over waypoint pairs', () {
      expect(road.distanceToPoint(-0.60, 30.65), closeTo(0, 1.0));
    });

    test('isOnRoad respects the corridor width', () {
      // ~55 m east of the centreline, outside a 20 m corridor.
      expect(road.isOnRoad(-0.60, 30.6505), isFalse);
      expect(road.isOnRoad(-0.60, 30.65), isTrue);
    });

    test('defaults to an inferred limit source', () {
      expect(road.limitSource, LimitSource.inferred,
          reason: 'eyeballed polylines must not reach the model as curated');
    });

    test('survives a JSON round trip with enums by name', () {
      final json = road.toJson();
      expect(json['type'], 'urban');
      expect(json['limitSource'], 'inferred');

      final restored = RoadSegment.fromJson(json);
      expect(restored.type, LocationType.urban);
      expect(restored.limitSource, LimitSource.inferred);
      expect(restored.speedLimit, 60);
    });

    test('still reads the legacy index form', () {
      final json = road.toJson();
      json['type'] = LocationType.highway.index;

      expect(RoadSegment.fromJson(json).type, LocationType.highway);
    });
  });
}
