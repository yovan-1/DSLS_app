import 'package:flutter_test/flutter_test.dart';
import 'package:dsls_app/models/trip_data.dart';
import 'package:dsls_app/models/speed_calculator.dart';

void main() {
  group('TripData', () {
    test('should create with required parameters', () {
      final trip = TripData(
        id: 'test-1',
        startTime: DateTime(2024, 1, 1, 10, 0),
        location: LocationType.urban,
        baseSpeedLimit: 60,
        recommendedSpeed: 50,
      );

      expect(trip.id, 'test-1');
      expect(trip.location, LocationType.urban);
      expect(trip.baseSpeedLimit, 60);
      expect(trip.recommendedSpeed, 50);
      expect(trip.maxSpeed, 0);
      expect(trip.avgSpeed, 0);
      expect(trip.overSpeedCount, 0);
      expect(trip.alerts, isEmpty);
    });

    test('copyWith should copy fields correctly', () {
      final trip = TripData(
        id: 'test-1',
        startTime: DateTime(2024, 1, 1, 10, 0),
        location: LocationType.urban,
        baseSpeedLimit: 60,
        recommendedSpeed: 50,
      );

      final updated = trip.copyWith(maxSpeed: 80, avgSpeed: 55);

      expect(updated.id, 'test-1');
      expect(updated.maxSpeed, 80);
      expect(updated.avgSpeed, 55);
      expect(updated.location, LocationType.urban);
    });

    test('duration should return null when endTime is null', () {
      final trip = TripData(
        id: 'test-1',
        startTime: DateTime(2024, 1, 1, 10, 0),
        location: LocationType.urban,
        baseSpeedLimit: 60,
        recommendedSpeed: 50,
      );

      expect(trip.duration, isNull);
    });

    test('duration should calculate when endTime is set', () {
      final trip = TripData(
        id: 'test-1',
        startTime: DateTime(2024, 1, 1, 10, 0),
        endTime: DateTime(2024, 1, 1, 11, 30),
        location: LocationType.urban,
        baseSpeedLimit: 60,
        recommendedSpeed: 50,
      );

      expect(trip.duration, equals(Duration(hours: 1, minutes: 30)));
    });

    test('formattedDuration should return minutes when under 1 hour', () {
      final trip = TripData(
        id: 'test-1',
        startTime: DateTime(2024, 1, 1, 10, 0),
        endTime: DateTime(2024, 1, 1, 10, 45),
        location: LocationType.urban,
        baseSpeedLimit: 60,
        recommendedSpeed: 50,
      );

      expect(trip.formattedDuration, '45m');
    });

    test('formattedDuration should return hours and minutes when over 1 hour', () {
      final trip = TripData(
        id: 'test-1',
        startTime: DateTime(2024, 1, 1, 10, 0),
        endTime: DateTime(2024, 1, 1, 12, 30),
        location: LocationType.urban,
        baseSpeedLimit: 60,
        recommendedSpeed: 50,
      );

      expect(trip.formattedDuration, '2h 30m');
    });

    test('formattedDuration should return In progress when no endTime', () {
      final trip = TripData(
        id: 'test-1',
        startTime: DateTime(2024, 1, 1, 10, 0),
        location: LocationType.urban,
        baseSpeedLimit: 60,
        recommendedSpeed: 50,
      );

      expect(trip.formattedDuration, 'In progress');
    });
  });

  group('TripData JSON serialization', () {
    test('toJson should serialize all fields', () {
      final trip = TripData(
        id: 'test-1',
        startTime: DateTime(2024, 1, 1, 10, 0),
        endTime: DateTime(2024, 1, 1, 11, 0),
        location: LocationType.highway,
        baseSpeedLimit: 100,
        recommendedSpeed: 80,
        maxSpeed: 90,
        avgSpeed: 70,
        overSpeedCount: 2,
        alerts: [],
      );

      final json = trip.toJson();

      expect(json['id'], 'test-1');
      // By name, not index: LocationType has already grown from six values to
      // eight, and index-based storage only survived that by luck.
      expect(json['location'], 'highway');
      expect(json['baseSpeedLimit'], 100);
      expect(json['recommendedSpeed'], 80);
      expect(json['maxSpeed'], 90);
      expect(json['avgSpeed'], 70);
      expect(json['overSpeedCount'], 2);
    });

    test('fromJson should deserialize all fields', () {
      final json = {
        'id': 'test-1',
        'startTime': '2024-01-01T10:00:00.000',
        'endTime': '2024-01-01T11:00:00.000',
        'location': LocationType.highway.index,
        'baseSpeedLimit': 100,
        'recommendedSpeed': 80,
        'maxSpeed': 90,
        'avgSpeed': 70,
        'overSpeedCount': 2,
        'alerts': <Map<String, dynamic>>[],
      };

      final trip = TripData.fromJson(json);

      expect(trip.id, 'test-1');
      expect(trip.location, LocationType.highway);
      expect(trip.baseSpeedLimit, 100);
      expect(trip.recommendedSpeed, 80);
      expect(trip.maxSpeed, 90);
      expect(trip.avgSpeed, 70);
      expect(trip.overSpeedCount, 2);
    });

    test('fromJson should handle null endTime', () {
      final json = {
        'id': 'test-1',
        'startTime': '2024-01-01T10:00:00.000',
        'endTime': null,
        'location': LocationType.urban.index,
        'baseSpeedLimit': 60,
        'recommendedSpeed': 50,
      };

      final trip = TripData.fromJson(json);

      expect(trip.endTime, isNull);
    });

    test('fromJson should handle missing optional fields', () {
      final json = {
        'id': 'test-1',
        'startTime': '2024-01-01T10:00:00.000',
        'location': LocationType.urban.index,
        'baseSpeedLimit': 60,
        'recommendedSpeed': 50,
      };

      final trip = TripData.fromJson(json);

      expect(trip.maxSpeed, 0);
      expect(trip.avgSpeed, 0);
      expect(trip.overSpeedCount, 0);
      expect(trip.alerts, isEmpty);
    });
  });

  group('SpeedAlert', () {
    test('should create with required parameters', () {
      final alert = SpeedAlert(
        id: 'alert-1',
        time: DateTime(2024, 1, 1, 10, 30),
        speed: 70,
        recommendedSpeed: 50,
        type: AlertType.overSpeed,
      );

      expect(alert.id, 'alert-1');
      expect(alert.speed, 70);
      expect(alert.recommendedSpeed, 50);
      expect(alert.type, AlertType.overSpeed);
    });

    test('toJson should serialize', () {
      final alert = SpeedAlert(
        id: 'alert-1',
        time: DateTime(2024, 1, 1, 10, 30),
        speed: 70,
        recommendedSpeed: 50,
        type: AlertType.overSpeed,
      );

      final json = alert.toJson();

      expect(json['id'], 'alert-1');
      expect(json['speed'], 70);
      expect(json['type'], 'overSpeed');
    });

    test('fromJson should deserialize', () {
      final json = {
        'id': 'alert-1',
        'time': '2024-01-01T10:30:00.000',
        'speed': 70,
        'recommendedSpeed': 50,
        'type': AlertType.overSpeed.index,
      };

      final alert = SpeedAlert.fromJson(json);

      expect(alert.id, 'alert-1');
      expect(alert.speed, 70);
      expect(alert.type, AlertType.overSpeed);
    });
  });

  group('AlertType', () {
    test('should have all values', () {
      expect(AlertType.values, contains(AlertType.overSpeed));
      expect(AlertType.values, contains(AlertType.harshBrake));
      expect(AlertType.values, contains(AlertType.rapidAcceleration));
      expect(AlertType.values, contains(AlertType.fatigueWarning));
    });
  });

  group('DrivingScore', () {
    test('should return zero for empty trips', () {
      final score = DrivingScore.calculate([]);

      expect(score.overall, 0);
      expect(score.speedCompliance, 0);
      expect(score.smoothness, 0);
      expect(score.attention, 0);
    });

    test('should calculate score based on trips', () {
      final trips = [
        TripData(
          id: 'trip-1',
          startTime: DateTime(2024, 1, 1, 10, 0),
          endTime: DateTime(2024, 1, 1, 11, 0),
          location: LocationType.highway,
          baseSpeedLimit: 100,
          recommendedSpeed: 80,
          overSpeedCount: 2,
          alerts: [
            SpeedAlert(
              id: 'alert-1',
              time: DateTime(2024, 1, 1, 10, 30),
              speed: 90,
              recommendedSpeed: 80,
              type: AlertType.overSpeed,
            ),
          ],
        ),
      ];

      final score = DrivingScore.calculate(trips);

      expect(score.overall, greaterThan(0));
      expect(score.speedCompliance, greaterThan(0));
      expect(score.smoothness, greaterThan(0));
    });

    /// The behaviour that made the score useless as feedback. It summed
    /// `overSpeedCount` across every trip ever and subtracted the clamped
    /// total, so after roughly ten lifetime over-speed episodes the score sat
    /// at its floor permanently — it could only ever decay.
    test('recovers after a bad trip is followed by good ones', () {
      TripData drive(String id, DateTime start, int overSpeeds) => TripData(
            id: id,
            startTime: start,
            endTime: start.add(const Duration(minutes: 30)),
            location: LocationType.urban,
            baseSpeedLimit: 60,
            recommendedSpeed: 50,
            overSpeedCount: overSpeeds,
          );

      final terrible = [drive('bad', DateTime(2026, 1, 1), 40)];
      final afterBad = DrivingScore.calculate(terrible).overall;

      // Ten clean drives after it.
      final recovered = [
        ...terrible,
        for (var i = 1; i <= 10; i++)
          drive('good$i', DateTime(2026, 1, 1 + i), 0),
      ];
      final afterGood = DrivingScore.calculate(recovered).overall;

      expect(afterGood, greaterThan(afterBad),
          reason: 'good driving must be able to move the score back up');
    });

    test('scores a window of recent trips, not all history', () {
      TripData drive(String id, DateTime start, int overSpeeds) => TripData(
            id: id,
            startTime: start,
            endTime: start.add(const Duration(minutes: 30)),
            location: LocationType.urban,
            baseSpeedLimit: 60,
            recommendedSpeed: 50,
            overSpeedCount: overSpeeds,
          );

      // One ancient disaster, then a full window of clean drives.
      final trips = [
        drive('ancient', DateTime(2020, 1, 1), 100),
        for (var i = 1; i <= DrivingScore.windowSize; i++)
          drive('recent$i', DateTime(2026, 1, i), 0),
      ];

      final score = DrivingScore.calculate(trips);

      expect(score.speedCompliance, 100,
          reason: 'a drive from 2020 should not still be scoring the driver');
    });

    test('scores a single trip on its own merits', () {
      final clean = TripData(
        id: 'clean',
        startTime: DateTime(2026, 1, 1),
        endTime: DateTime(2026, 1, 1, 0, 30),
        location: LocationType.urban,
        baseSpeedLimit: 60,
        recommendedSpeed: 50,
      );

      expect(DrivingScore.forTrip(clean).speedCompliance, 100);
      expect(DrivingScore.forTrip(clean).overall, greaterThan(90));
    });

    test('grade should return correct grade', () {
      expect(const DrivingScore(overall: 95, speedCompliance: 90, smoothness: 90, attention: 90).grade, 'A+');
      expect(const DrivingScore(overall: 85, speedCompliance: 80, smoothness: 80, attention: 80).grade, 'A');
      expect(const DrivingScore(overall: 75, speedCompliance: 70, smoothness: 70, attention: 70).grade, 'B');
      expect(const DrivingScore(overall: 65, speedCompliance: 60, smoothness: 60, attention: 60).grade, 'C');
      expect(const DrivingScore(overall: 55, speedCompliance: 50, smoothness: 50, attention: 50).grade, 'D');
      expect(const DrivingScore(overall: 40, speedCompliance: 30, smoothness: 30, attention: 30).grade, 'F');
    });

    test('description should return correct description', () {
      expect(const DrivingScore(overall: 90, speedCompliance: 90, smoothness: 90, attention: 90).description, 'Excellent driving');
      expect(const DrivingScore(overall: 70, speedCompliance: 70, smoothness: 70, attention: 70).description, 'Good driving');
      expect(const DrivingScore(overall: 50, speedCompliance: 50, smoothness: 50, attention: 50).description, 'Needs improvement');
      expect(const DrivingScore(overall: 30, speedCompliance: 30, smoothness: 30, attention: 30).description, 'Poor driving');
    });

    test('overall should be clamped to 0-100', () {
      final trips = [
        TripData(
          id: 'trip-1',
          startTime: DateTime(2024, 1, 1, 10, 0),
          endTime: DateTime(2024, 1, 1, 11, 0),
          location: LocationType.highway,
          baseSpeedLimit: 100,
          recommendedSpeed: 80,
          overSpeedCount: 100,
          alerts: List.generate(
            50,
            (i) => SpeedAlert(
              id: 'alert-$i',
              time: DateTime(2024, 1, 1, 10, 30),
              speed: 90,
              recommendedSpeed: 80,
              type: AlertType.overSpeed,
            ),
          ),
        ),
      ];

      final score = DrivingScore.calculate(trips);

      expect(score.overall, greaterThanOrEqualTo(0));
      expect(score.overall, lessThanOrEqualTo(100));
    });
  });
}