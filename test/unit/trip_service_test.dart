import 'package:dsls_app/models/speed_calculator.dart' show LocationType, WeatherCondition;
import 'package:dsls_app/models/speed_model/road_conditions.dart';
import 'package:dsls_app/models/speed_model/solar_position.dart';
import 'package:dsls_app/models/speed_model/speed_recommendation.dart';
import 'package:dsls_app/services/trip_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _conditions = RoadConditions(
  speedLimitKph: 60,
  limitSource: LimitSource.curated,
  roadClass: LocationType.urban,
  weather: WeatherCondition.clear,
  daylight: DaylightState.daylight,
);

void main() {
  late TripService trips;

  setUp(() {
    trips = TripService();
    trips.startTrip(_conditions);
  });

  void record(int speed, {int limit = 60}) {
    trips.addRecord(
      speed: speed,
      recommendedSpeed: limit,
      riskBand: RiskBand.low,
    );
  }

  group('overSpeedCount counts episodes, not samples', () {
    test('a sustained overspeed is one episode however often it is sampled', () {
      for (var i = 0; i < 20; i++) {
        record(90);
      }

      expect(trips.drivingRecords.length, 20);
      expect(trips.currentTrip!.overSpeedCount, 1,
          reason: 'twenty samples of one overspeed is still one overspeed');
      expect(trips.currentTrip!.alerts.length, 1);
    });

    test('dropping back under and going over again is a second episode', () {
      record(90);
      record(90);
      record(40);
      record(90);

      expect(trips.currentTrip!.overSpeedCount, 2);
      expect(trips.currentTrip!.alerts.length, 2);
    });

    test('the first record being over-speed counts', () {
      record(90);

      expect(trips.currentTrip!.overSpeedCount, 1);
    });

    test('staying under the limit counts nothing', () {
      for (var i = 0; i < 10; i++) {
        record(40);
      }

      expect(trips.currentTrip!.overSpeedCount, 0);
      expect(trips.currentTrip!.alerts, isEmpty);
    });

    test('alternating every sample counts each crossing once', () {
      for (var i = 0; i < 5; i++) {
        record(90);
        record(40);
      }

      expect(trips.currentTrip!.overSpeedCount, 5);
    });
  });

  group('alert episodes', () {
    test('an episode tracks the worst speed reached, not just the first', () {
      record(85);
      record(110);
      record(95);

      final alert = trips.currentTrip!.alerts.single;
      expect(alert.speed, 85, reason: 'the speed the episode opened at');
      expect(alert.peakSpeed, 110, reason: 'the worst point of the episode');
    });

    test('an episode closes when the driver comes back under', () {
      record(90);
      record(90);
      record(40);

      final alert = trips.currentTrip!.alerts.single;
      expect(alert.isOpen, isFalse);
      expect(alert.endTime, isNotNull);
    });

    test('an episode stays open while the driver is still over', () {
      record(90);
      record(90);

      expect(trips.currentTrip!.alerts.single.isOpen, isTrue);
    });

    test('a trip ending mid-overspeed still closes its episode', () async {
      record(90);
      expect(trips.currentTrip!.alerts.single.isOpen, isTrue);

      await trips.endTrip();

      expect(trips.trips.single.alerts.single.isOpen, isFalse,
          reason: 'an open episode would have no duration for ever');
    });
  });

  group('distance', () {
    /// Distance used to be derived from `duration x avgSpeed`, which counts
    /// time spent stationary at a junction as ground covered.
    test('accumulates measured legs', () {
      trips.addDistance(1200);
      trips.addDistance(800);

      expect(trips.distanceMetres, 2000);
    });

    test('is written onto the completed trip', () async {
      record(50);
      trips.addDistance(4321);

      await trips.endTrip();

      expect(trips.trips.single.distanceTraveledMeters, 4321);
    });

    test('ignores non-positive legs', () {
      trips.addDistance(100);
      trips.addDistance(0);
      trips.addDistance(-50);

      expect(trips.distanceMetres, 100);
    });

    test('resets between trips', () {
      trips.addDistance(500);
      trips.startTrip(_conditions);

      expect(trips.distanceMetres, 0);
    });
  });

  group('risk score', () {
    test('averages the risk bands actually recorded', () {
      // RiskBand.low has index 0, so an all-low trip averages to zero.
      record(40);
      record(40);

      expect(trips.currentTrip!.avgRiskScore, 0);
    });
  });

  group('trip statistics', () {
    test('tracks max and average speed across records', () {
      record(40);
      record(60);
      record(50);

      expect(trips.currentTrip!.maxSpeed, 60);
      expect(trips.currentTrip!.avgSpeed, 50);
    });

    test('records are ignored when no trip is running', () async {
      await trips.endTrip();

      record(90);

      expect(trips.drivingRecords.length, 0);
    });
  });
}
