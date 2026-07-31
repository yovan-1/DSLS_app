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
