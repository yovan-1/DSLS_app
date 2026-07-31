import 'package:dsls_app/models/road_segment.dart';
import 'package:dsls_app/models/speed_calculator.dart' show LocationType;
import 'package:dsls_app/models/speed_model/road_conditions.dart'
    show LimitSource;
import 'package:dsls_app/models/speed_zone.dart';
import 'package:dsls_app/services/location_speed_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Roughly one metre in degrees of latitude near the equator.
const metre = 1 / 111194.0;

SpeedZone zone({
  required String id,
  required double lat,
  required double lon,
  required int limit,
  required int radius,
  LocationType type = LocationType.urban,
}) =>
    SpeedZone(
      id: id,
      name: id,
      latitude: lat,
      longitude: lon,
      speedLimit: limit,
      triggerRadius: radius,
      type: type,
    );

void main() {
  late LocationSpeedService service;

  setUp(() => service = LocationSpeedService());

  group('inside beats approaching', () {
    /// The original checked "inside this zone?" and "approaching this zone?"
    /// in the same loop iteration and returned immediately, so whichever zone
    /// happened to be visited first won — a zone merely being approached could
    /// beat one the driver was physically inside.
    test('a zone you are inside wins over one you are approaching', () {
      service.initialize([
        // Big, permissive, centred 150 m north — its approach ring reaches us.
        zone(id: 'city', lat: 150 * metre, lon: 0, limit: 60, radius: 100),
        // Small, strict, centred right on us.
        zone(
          id: 'school',
          lat: 0,
          lon: 0,
          limit: 30,
          radius: 50,
          type: LocationType.schoolZone,
        ),
      ], []);

      service.updatePosition(0, 0, speedKph: 60);

      expect(service.currentResult.status, LocationSpeedStatus.inZone);
      expect(service.currentResult.speedLimit, 30);
      expect(service.currentResult.activeZoneName, 'school');
    });
  });

  group('nearest match, not first match', () {
    test('the closer of two overlapping zones wins', () {
      service.initialize([
        zone(id: 'far', lat: 80 * metre, lon: 0, limit: 60, radius: 100),
        zone(id: 'near', lat: 10 * metre, lon: 0, limit: 40, radius: 100),
      ], []);

      service.updatePosition(0, 0);

      expect(service.currentResult.activeZoneName, 'near');
      expect(service.currentResult.speedLimit, 40);
    });

    test('order of declaration does not decide the outcome', () {
      final a = zone(id: 'far', lat: 80 * metre, lon: 0, limit: 60, radius: 100);
      final b = zone(id: 'near', lat: 10 * metre, lon: 0, limit: 40, radius: 100);

      final forward = LocationSpeedService()..initialize([a, b], []);
      final reversed = LocationSpeedService()..initialize([b, a], []);

      forward.updatePosition(0, 0);
      reversed.updatePosition(0, 0);

      expect(forward.currentResult.speedLimit, reversed.currentResult.speedLimit);
      expect(forward.currentResult.activeZoneName,
          reversed.currentResult.activeZoneName);
    });

    test('equidistant zones resolve to the stricter limit', () {
      service.initialize([
        zone(id: 'permissive', lat: 0, lon: 0, limit: 60, radius: 100),
        zone(id: 'strict', lat: 0, lon: 0, limit: 30, radius: 100),
      ], []);

      service.updatePosition(0, 0);

      expect(service.currentResult.speedLimit, 30,
          reason: 'the cautious error is the cheaper one for a speed advisory');
    });

    /// The concrete failure the missing `==`/`hashCode` on `SpeedZone` caused:
    /// candidates were unioned into a `Set`, so iteration ran in identity-hash
    /// order and the same coordinate could yield different limits run to run.
    test('the same coordinate always gives the same answer', () {
      final zones = [
        zone(id: 'a', lat: 20 * metre, lon: 0, limit: 60, radius: 100),
        zone(id: 'b', lat: 20 * metre, lon: 0, limit: 50, radius: 100),
        zone(id: 'c', lat: 20 * metre, lon: 0, limit: 40, radius: 100),
      ];

      final results = <int>{};
      for (var i = 0; i < 50; i++) {
        final s = LocationSpeedService()..initialize(zones, []);
        s.updatePosition(0, 0);
        results.add(s.currentResult.speedLimit);
      }

      expect(results, hasLength(1),
          reason: 'a speed limit must not depend on hash iteration order');
    });
  });

  group('approach is heading-aware and speed-scaled', () {
    test('fires when closing on a zone', () {
      service.initialize(
          [zone(id: 'school', lat: 0, lon: 0, limit: 30, radius: 50)], []);

      // 300 m out, then 200 m out: closing.
      service.updatePosition(300 * metre, 0, speedKph: 80);
      service.updatePosition(200 * metre, 0, speedKph: 80);

      expect(service.currentResult.status, LocationSpeedStatus.approachingZone);
      expect(service.currentResult.activeZoneName, contains('approaching'));
    });

    /// The old ring was a flat `2 × triggerRadius` with no direction test, so
    /// driving away from a zone raised a fresh approach alert.
    test('does not fire when leaving a zone', () {
      service.initialize(
          [zone(id: 'school', lat: 0, lon: 0, limit: 30, radius: 50)], []);

      // 100 m out, then 200 m out: receding.
      service.updatePosition(100 * metre, 0, speedKph: 80);
      service.updatePosition(200 * metre, 0, speedKph: 80);

      expect(service.currentResult.status, isNot(LocationSpeedStatus.approachingZone));
    });

    test('a fast approach gets warning further out than a slow one', () {
      LocationSpeedStatus statusAt(double speedKph) {
        final s = LocationSpeedService()
          ..initialize(
              [zone(id: 'z', lat: 0, lon: 0, limit: 30, radius: 10)], []);
        s.updatePosition(200 * metre, 0, speedKph: speedKph);
        s.updatePosition(150 * metre, 0, speedKph: speedKph);
        return s.currentResult.status;
      }

      // At 80 km/h the ring is 10 m + 22.2 m/s x 8 s = ~188 m, so 150 m is inside.
      expect(statusAt(80), LocationSpeedStatus.approachingZone);
      // At 10 km/h it is 10 m + 2.8 m/s x 8 s = ~32 m, so 150 m is not.
      expect(statusAt(10), isNot(LocationSpeedStatus.approachingZone));
    });

    test('no approach alert on the very first fix', () {
      service.initialize(
          [zone(id: 'z', lat: 0, lon: 0, limit: 30, radius: 50)], []);

      service.updatePosition(200 * metre, 0, speedKph: 80);

      expect(service.currentResult.status, isNot(LocationSpeedStatus.approachingZone),
          reason: 'closing cannot be determined without a previous fix');
    });
  });

  group('road matching', () {
    RoadSegment road(String id, double lon, int limit) => RoadSegment(
          id: id,
          name: id,
          waypoints: [
            MapPoint(latitude: -0.01, longitude: lon),
            MapPoint(latitude: 0.01, longitude: lon),
          ],
          speedLimit: limit,
          widthMeters: 20,
          type: LocationType.urban,
        );

    test('reports the nearest road, not the first declared', () {
      service.initialize([], [
        road('far', 15 * metre, 80),
        road('near', 2 * metre, 50),
      ]);

      service.updatePosition(0, 0);

      expect(service.currentResult.activeRoadName, 'near');
      expect(service.currentResult.status, LocationSpeedStatus.onRoad);
    });

    test('a road match carries its limit source', () {
      service.initialize([], [road('r', 0, 50)]);

      service.updatePosition(0, 0);

      expect(service.currentResult.limitSource, LimitSource.inferred,
          reason: 'hand-drawn polylines must not claim full confidence');
    });

    test('falls back to the default result off every road', () {
      service.initialize([], [road('r', 0, 50)]);

      service.updatePosition(0, 1000 * metre);

      expect(service.currentResult.status, LocationSpeedStatus.none);
      expect(service.currentResult.limitSource, LimitSource.inferred);
    });

    test('zones take priority over roads', () {
      service.initialize(
        [zone(id: 'school', lat: 0, lon: 0, limit: 30, radius: 50)],
        [road('r', 0, 80)],
      );

      service.updatePosition(0, 0);

      expect(service.currentResult.status, LocationSpeedStatus.inZone);
      expect(service.currentResult.speedLimit, 30);
    });
  });

  group('map-matching hysteresis', () {
    RoadSegment parallel(String id, double lon, int limit) => RoadSegment(
          id: id,
          name: id,
          waypoints: [
            MapPoint(latitude: -0.01, longitude: lon),
            MapPoint(latitude: 0.01, longitude: lon),
          ],
          speedLimit: limit,
          widthMeters: 20,
          type: LocationType.urban,
        );

    test('a single noisy fix does not switch the active road', () {
      service.initialize([], [
        parallel('main', 0, 80),
        parallel('slip', 15 * metre, 30),
      ]);

      // Settle on the main road.
      service.updatePosition(0, 0);
      expect(service.currentResult.activeRoadName, 'main');

      // One fix that lands nearer the slip road.
      service.updatePosition(0, 15 * metre);

      expect(service.currentResult.activeRoadName, 'main',
          reason: 'the ceiling must not flap on one noisy fix at a junction');
    });

    test('a sustained move does switch the active road', () {
      service.initialize([], [
        parallel('main', 0, 80),
        parallel('slip', 15 * metre, 30),
      ]);

      service.updatePosition(0, 0);
      for (var i = 0; i < LocationSpeedService.roadSwitchFixes; i++) {
        service.updatePosition(0, 15 * metre);
      }

      expect(service.currentResult.activeRoadName, 'slip');
      expect(service.currentResult.speedLimit, 30);
    });

    test('the first road ever matched engages immediately', () {
      service.initialize([], [parallel('main', 0, 80)]);

      service.updatePosition(0, 0);

      expect(service.currentResult.activeRoadName, 'main',
          reason: 'hysteresis should not delay the initial match');
    });
  });

  group('reset', () {
    test('clears the result and the hysteresis state', () {
      service.initialize(
          [zone(id: 'z', lat: 0, lon: 0, limit: 30, radius: 50)], []);
      service.updatePosition(0, 0);
      expect(service.currentResult.status, LocationSpeedStatus.inZone);

      service.reset();

      expect(service.currentResult.status, LocationSpeedStatus.none);
      expect(service.currentLat, isNull);
    });
  });
}
