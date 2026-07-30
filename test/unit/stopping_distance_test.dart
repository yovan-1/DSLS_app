import 'package:flutter_test/flutter_test.dart';
import 'package:dsls_app/models/speed_model/friction_model.dart';
import 'package:dsls_app/models/speed_model/stopping_distance.dart';

void main() {
  group('stoppingDistanceMetres', () {
    test('is zero at rest', () {
      expect(
        StoppingDistance.stoppingDistanceMetres(
          0,
          friction: FrictionModel.dryFriction,
        ),
        0,
      );
    });

    test('reproduces AASHTO design stopping sight distances', () {
      // AASHTO Green Book, Table 3-1 (level grade, 2.5 s reaction,
      // 3.4 m/s² deceleration). These are the published design values, so the
      // model should land within a metre or two of each.
      const aashtoSsdMetres = <(double, double)>[
        (50, 65),
        (60, 85),
        (80, 130),
        (100, 185),
        (120, 250),
      ];

      for (final (speedKph, expectedMetres) in aashtoSsdMetres) {
        final actual = StoppingDistance.stoppingDistanceMetres(
          speedKph,
          friction: FrictionModel.dryFriction,
        );
        expect(
          actual,
          closeTo(expectedMetres, 6),
          reason: 'SSD at $speedKph km/h should be about $expectedMetres m',
        );
      }
    });

    test('grows faster than linearly with speed', () {
      // Braking distance is quadratic, so doubling speed more than doubles the
      // total. This is the property drivers most consistently underestimate.
      final at40 = StoppingDistance.stoppingDistanceMetres(
        40,
        friction: FrictionModel.dryFriction,
      );
      final at80 = StoppingDistance.stoppingDistanceMetres(
        80,
        friction: FrictionModel.dryFriction,
      );

      expect(at80, greaterThan(2 * at40));
    });

    test('is longer on lower friction', () {
      final dry = StoppingDistance.stoppingDistanceMetres(
        60,
        friction: FrictionModel.frictionFor(SurfaceState.dry),
      );
      final wet = StoppingDistance.stoppingDistanceMetres(
        60,
        friction: FrictionModel.frictionFor(SurfaceState.wet),
      );
      final ice = StoppingDistance.stoppingDistanceMetres(
        60,
        friction: FrictionModel.frictionFor(SurfaceState.ice),
      );

      expect(wet, greaterThan(dry));
      expect(ice, greaterThan(wet));
    });
  });

  group('maxSpeedForSightDistance', () {
    test('is the exact inverse of stoppingDistanceMetres', () {
      for (final speed in [20.0, 40.0, 60.0, 80.0, 100.0, 130.0]) {
        for (final surface in SurfaceState.values) {
          final friction = FrictionModel.frictionFor(surface);
          final distance = StoppingDistance.stoppingDistanceMetres(
            speed,
            friction: friction,
          );
          final recovered = StoppingDistance.maxSpeedForSightDistance(
            distance,
            friction: friction,
          );

          expect(
            recovered,
            closeTo(speed, 0.001),
            reason: 'round trip failed at $speed km/h on ${surface.name}',
          );
        }
      }
    });

    test('is zero when nothing can be seen', () {
      expect(
        StoppingDistance.maxSpeedForSightDistance(
          0,
          friction: FrictionModel.dryFriction,
        ),
        0,
      );
    });

    test('low-beam headlights bound night speed well below motorway limits',
        () {
      // 60 m of low beam does not support 100 km/h, which is the core insight
      // the old hour-bucket model could not express.
      final v = StoppingDistance.maxSpeedForSightDistance(
        60,
        friction: FrictionModel.dryFriction,
      );

      expect(v, lessThan(60));
      expect(v, greaterThan(30));
    });

    test('increases monotonically with sight distance', () {
      var previous = 0.0;
      for (var s = 10.0; s <= 500; s += 10) {
        final v = StoppingDistance.maxSpeedForSightDistance(
          s,
          friction: FrictionModel.dryFriction,
        );
        expect(v, greaterThan(previous));
        previous = v;
      }
    });
  });
}
