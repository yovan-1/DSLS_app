import 'dart:math' as math;

import 'package:dsls_app/models/motion/dead_reckoning.dart';
import 'package:flutter_test/flutter_test.dart';

/// Earth gravity as the accelerometer reports it, for a phone in an arbitrary
/// pose. `down` is the direction gravity points in device axes.
Vector3 _gravityReading(Vector3 down) => (down.normalized ?? down) * 9.81;

/// Settles the gravity low-pass by feeding the same reading repeatedly, as a
/// stationary phone would.
void _establishGravity(DeadReckoningEstimator e, Vector3 down) {
  final reading = _gravityReading(down);
  for (var i = 0; i < 600; i++) {
    e.addRawAccel(reading);
  }
}

/// Drives the estimator for [seconds] at a steady longitudinal acceleration of
/// [accel] m/s² along [forward], sampling at 50 Hz.
void _drive(
  DeadReckoningEstimator e, {
  required Vector3 forward,
  required double accel,
  required double seconds,
  Vector3 down = const Vector3(0, 0, -1),
}) {
  const dt = 0.02;
  final unitForward = forward.normalized!;
  final steps = (seconds / dt).round();
  final gravity = _gravityReading(down);
  for (var i = 0; i < steps; i++) {
    e.addRawAccel(gravity);
    e.addUserAccel(unitForward * accel, dt);
  }
}

void main() {
  group('Vector3', () {
    test('normalizes to unit length', () {
      final v = const Vector3(3, 4, 0).normalized!;
      expect(v.magnitude, closeTo(1.0, 1e-9));
      expect(v.x, closeTo(0.6, 1e-9));
      expect(v.y, closeTo(0.8, 1e-9));
    });

    test('has no direction at zero length', () {
      expect(Vector3.zero.normalized, isNull);
    });

    test('dot product of perpendicular vectors is zero', () {
      expect(const Vector3(1, 0, 0).dot(const Vector3(0, 1, 0)), 0);
    });
  });

  group('gravity tracking', () {
    test('is unknown until samples arrive', () {
      expect(DeadReckoningEstimator().gravityKnown, isFalse);
    });

    test('settles on the direction of a stationary phone', () {
      final e = DeadReckoningEstimator();
      _establishGravity(e, const Vector3(0, -1, 0));

      expect(e.gravityKnown, isTrue);
    });
  });

  group('orientation is learned, not assumed', () {
    test('starts unknown', () {
      final e = DeadReckoningEstimator();
      _establishGravity(e, const Vector3(0, 0, -1));

      expect(e.orientationKnown, isFalse);
    });

    test('does not integrate before the forward axis is known', () {
      final e = DeadReckoningEstimator();
      _establishGravity(e, const Vector3(0, 0, -1));
      e.zeroAgainstGps(10);

      _drive(e, forward: const Vector3(1, 0, 0), accel: 2.0, seconds: 2);

      expect(e.orientationKnown, isFalse);
      expect(e.speedEstimateMps, 10,
          reason: 'holds the last GPS speed rather than guessing an axis');
    });

    test('recovers the forward axis from a GPS interval', () {
      final e = DeadReckoningEstimator();
      const forward = Vector3(1, 0, 0);
      _establishGravity(e, const Vector3(0, 0, -1));

      e.zeroAgainstGps(10);
      _drive(e, forward: forward, accel: 2.0, seconds: 2);
      e.zeroAgainstGps(14); // +4 m/s over 2 s = 2 m/s², consistent

      expect(e.orientationKnown, isTrue);
      final axis = e.forwardAxis!;
      expect(axis.x, closeTo(1.0, 0.05));
      expect(axis.y, closeTo(0.0, 0.05));
      expect(axis.z, closeTo(0.0, 0.05));
    });

    test('recovers a forward axis that is not a device axis', () {
      final e = DeadReckoningEstimator();
      // Phone lying at 30° to the direction of travel — the case the old
      // hard-coded `-y` forward axis got badly wrong.
      final forward =
          Vector3(math.cos(math.pi / 6), math.sin(math.pi / 6), 0).normalized!;
      _establishGravity(e, const Vector3(0, 0, -1));

      e.zeroAgainstGps(10);
      _drive(e, forward: forward, accel: 2.0, seconds: 2);
      e.zeroAgainstGps(14);

      final axis = e.forwardAxis!;
      expect(axis.dot(forward), closeTo(1.0, 0.05),
          reason: 'the learned axis should align with the true one');
    });

    test('orients the axis correctly when braking', () {
      final e = DeadReckoningEstimator();
      const forward = Vector3(1, 0, 0);
      _establishGravity(e, const Vector3(0, 0, -1));

      e.zeroAgainstGps(20);
      // Decelerating: acceleration points backwards along travel.
      _drive(e, forward: forward, accel: -3.0, seconds: 2);
      e.zeroAgainstGps(14); // -6 m/s over 2 s = -3 m/s²

      final axis = e.forwardAxis!;
      expect(axis.x, closeTo(1.0, 0.05),
          reason: 'a deceleration must not flip the forward axis');
    });

    test('a phone in a different pose still yields a horizontal axis', () {
      final e = DeadReckoningEstimator();
      // Phone flat on its back: gravity along -z; travel along +y.
      const down = Vector3(0, 0, -1);
      const forward = Vector3(0, 1, 0);
      _establishGravity(e, down);

      e.zeroAgainstGps(10);
      _drive(e, forward: forward, accel: 2.0, seconds: 2, down: down);
      e.zeroAgainstGps(14);

      final axis = e.forwardAxis!;
      expect(axis.dot(forward), closeTo(1.0, 0.05));
      expect(axis.dot(down.normalized!).abs(), closeTo(0.0, 0.05),
          reason: 'the forward axis must lie in the road plane');
    });

    test('ignores intervals too gentle to carry direction', () {
      final e = DeadReckoningEstimator();
      _establishGravity(e, const Vector3(0, 0, -1));

      e.zeroAgainstGps(10);
      _drive(e, forward: const Vector3(1, 0, 0), accel: 0.05, seconds: 2);
      e.zeroAgainstGps(10.1);

      expect(e.orientationKnown, isFalse,
          reason: 'noise-level acceleration says nothing about direction');
    });
  });

  group('integration and drift', () {
    test('integrates along the learned axis', () {
      final e = DeadReckoningEstimator();
      const forward = Vector3(1, 0, 0);
      _establishGravity(e, const Vector3(0, 0, -1));

      e.zeroAgainstGps(10);
      _drive(e, forward: forward, accel: 2.0, seconds: 2);
      e.zeroAgainstGps(14);

      // Now dead-reckon for another second at the same acceleration.
      _drive(e, forward: forward, accel: 2.0, seconds: 1);

      expect(e.speedEstimateMps, closeTo(16, 0.3));
    });

    test('a GPS fix bounds drift no matter how wrong the integrator was', () {
      final e = DeadReckoningEstimator();
      const forward = Vector3(1, 0, 0);
      _establishGravity(e, const Vector3(0, 0, -1));

      e.zeroAgainstGps(10);
      _drive(e, forward: forward, accel: 2.0, seconds: 2);
      e.zeroAgainstGps(14);

      // Integrate a long way off.
      _drive(e, forward: forward, accel: 3.0, seconds: 8);
      expect(e.speedEstimateMps, greaterThan(30));

      // One fix and the error is gone.
      e.zeroAgainstGps(12);
      expect(e.speedEstimateMps, 12);
    });

    test('tracks how long it has been dead-reckoning', () {
      final e = DeadReckoningEstimator();
      _establishGravity(e, const Vector3(0, 0, -1));
      e.zeroAgainstGps(10);

      _drive(e, forward: const Vector3(1, 0, 0), accel: 2.0, seconds: 2);

      expect(e.secondsSinceGpsFix, closeTo(2.0, 0.1));
      e.zeroAgainstGps(14);
      expect(e.secondsSinceGpsFix, 0);
    });

    test('never reports a negative speed', () {
      final e = DeadReckoningEstimator();
      const forward = Vector3(1, 0, 0);
      _establishGravity(e, const Vector3(0, 0, -1));

      e.zeroAgainstGps(10);
      _drive(e, forward: forward, accel: 2.0, seconds: 2);
      e.zeroAgainstGps(14);

      _drive(e, forward: forward, accel: -5.0, seconds: 10);

      expect(e.speedEstimateMps, 0);
    });

    test('rejects implausible time steps', () {
      final e = DeadReckoningEstimator();
      const forward = Vector3(1, 0, 0);
      _establishGravity(e, const Vector3(0, 0, -1));
      e.zeroAgainstGps(10);
      _drive(e, forward: forward, accel: 2.0, seconds: 2);
      e.zeroAgainstGps(14);

      // A 30-second gap — the app was suspended, not the car accelerating.
      e.addUserAccel(forward * 5, 30);

      expect(e.speedEstimateMps, 14);
    });
  });

  group('reset', () {
    test('forgets the learned orientation', () {
      final e = DeadReckoningEstimator();
      _establishGravity(e, const Vector3(0, 0, -1));
      e.zeroAgainstGps(10);
      _drive(e, forward: const Vector3(1, 0, 0), accel: 2.0, seconds: 2);
      e.zeroAgainstGps(14);
      expect(e.orientationKnown, isTrue);

      e.reset();

      expect(e.orientationKnown, isFalse);
      expect(e.gravityKnown, isFalse);
      expect(e.speedEstimateMps, 0);
    });
  });
}
