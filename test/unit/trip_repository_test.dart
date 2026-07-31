import 'dart:io';

import 'package:dsls_app/models/speed_calculator.dart' show LocationType;
import 'package:dsls_app/models/speed_model/speed_recommendation.dart'
    show RiskBand;
import 'package:dsls_app/models/trip_data.dart';
import 'package:dsls_app/services/trip_repository.dart';
import 'package:dsls_app/services/trip_service.dart' show DrivingRecord;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

TripData trip({
  String id = 't1',
  DateTime? start,
  int overSpeedCount = 0,
  List<SpeedAlert> alerts = const [],
  int distanceMetres = 0,
  double avgRisk = 0,
  String? roadSegmentId,
  String? surface,
  int? actualLimit,
}) =>
    TripData(
      id: id,
      startTime: start ?? DateTime(2026, 7, 31, 8),
      endTime: (start ?? DateTime(2026, 7, 31, 8)).add(const Duration(hours: 1)),
      location: LocationType.highway,
      baseSpeedLimit: 80,
      recommendedSpeed: 70,
      maxSpeed: 95,
      avgSpeed: 62,
      overSpeedCount: overSpeedCount,
      alerts: alerts,
      roadSegmentId: roadSegmentId,
      actualSpeedLimit: actualLimit,
      estimatedSurface: surface,
      avgRiskScore: avgRisk,
      distanceTraveledMeters: distanceMetres,
    );

void main() {
  late TripRepository repository;
  late Directory tempDir;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('trip_repo_test');
    repository = TripRepository();
    await repository.open(
      factoryOverride: databaseFactoryFfi,
      path: '${tempDir.path}/trips.db',
    );
  });

  tearDown(() async {
    await repository.close();
    await tempDir.delete(recursive: true);
  });

  group('round trip', () {
    test('a saved trip comes back intact', () async {
      await repository.saveTrip(trip(distanceMetres: 12345, avgRisk: 1.5));

      final loaded = await repository.loadTrips();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 't1');
      expect(loaded.single.location, LocationType.highway);
      expect(loaded.single.maxSpeed, 95);
      expect(loaded.single.distanceTraveledMeters, 12345);
      expect(loaded.single.avgRiskScore, 1.5);
    });

    /// These five were declared, uploaded to S3 and never assigned — every
    /// uploaded trip carried five null or zero columns.
    test('the previously-dead fields persist', () async {
      await repository.saveTrip(trip(
        roadSegmentId: '4821',
        actualLimit: 80,
        surface: 'unpaved',
        avgRisk: 2.25,
        distanceMetres: 9000,
      ));

      final loaded = (await repository.loadTrips()).single;

      expect(loaded.roadSegmentId, '4821');
      expect(loaded.actualSpeedLimit, 80);
      expect(loaded.estimatedSurface, 'unpaved');
      expect(loaded.avgRiskScore, 2.25);
      expect(loaded.distanceTraveledMeters, 9000);
    });

    test('saving the same trip twice does not duplicate it', () async {
      await repository.saveTrip(trip());
      await repository.saveTrip(trip(overSpeedCount: 3));

      final loaded = await repository.loadTrips();

      expect(loaded, hasLength(1));
      expect(loaded.single.overSpeedCount, 3);
    });

    test('trips come back newest first', () async {
      await repository.saveTrip(trip(id: 'old', start: DateTime(2026, 1, 1)));
      await repository.saveTrip(trip(id: 'new', start: DateTime(2026, 7, 1)));

      final loaded = await repository.loadTrips();

      expect(loaded.map((t) => t.id), ['new', 'old']);
    });
  });

  group('driving records', () {
    /// DrivingRecord had no `toJson` at all, so the safe/moderate/risky
    /// percentages were computed from an in-memory list that cleared on the
    /// next trip — every one of those numbers was meaningless after a restart.
    test('survive a save and reload', () async {
      final records = List.generate(
        5,
        (i) => DrivingRecord(
          speed: 60 + i,
          recommendedSpeed: 70,
          riskBand: RiskBand.moderate,
          isOverSpeed: false,
          timestamp: DateTime(2026, 7, 31, 8, 0, i),
        ),
      );

      await repository.saveTrip(trip(), records: records);
      final loaded = await repository.recordsFor('t1');

      expect(loaded, hasLength(5));
      expect(loaded.first.speed, 60);
      expect(loaded.last.speed, 64);
      expect(loaded.first.riskBand, RiskBand.moderate);
    });

    test('are replaced, not appended, when a trip is re-saved', () async {
      final one = [
        DrivingRecord(
          speed: 50,
          recommendedSpeed: 70,
          riskBand: RiskBand.low,
          isOverSpeed: false,
          timestamp: DateTime(2026, 7, 31, 8),
        ),
      ];

      await repository.saveTrip(trip(), records: one);
      await repository.saveTrip(trip(), records: one);

      expect(await repository.recordsFor('t1'), hasLength(1));
    });

    test('go away with their trip', () async {
      await repository.saveTrip(trip(), records: [
        DrivingRecord(
          speed: 50,
          recommendedSpeed: 70,
          riskBand: RiskBand.low,
          isOverSpeed: false,
          timestamp: DateTime(2026, 7, 31, 8),
        ),
      ]);

      await repository.deleteTrip('t1');

      expect(await repository.recordsFor('t1'), isEmpty,
          reason: 'the foreign key cascade should take them');
    });
  });

  group('alert episodes', () {
    test('carry start, end and peak', () async {
      final alert = SpeedAlert(
        id: 'a1',
        time: DateTime(2026, 7, 31, 8, 10),
        endTime: DateTime(2026, 7, 31, 8, 12),
        speed: 85,
        peakSpeed: 103,
        recommendedSpeed: 70,
        type: AlertType.overSpeed,
      );

      await repository.saveTrip(trip(alerts: [alert]));
      final loaded = (await repository.loadTrips()).single;

      expect(loaded.alerts, hasLength(1));
      expect(loaded.alerts.single.peakSpeed, 103);
      expect(loaded.alerts.single.duration, const Duration(minutes: 2));
      expect(loaded.alerts.single.isOpen, isFalse);
    });

    test('an open episode round-trips as open', () async {
      final alert = SpeedAlert(
        id: 'a1',
        time: DateTime(2026, 7, 31, 8, 10),
        speed: 85,
        recommendedSpeed: 70,
        type: AlertType.overSpeed,
      );

      await repository.saveTrip(trip(alerts: [alert]));
      final loaded = (await repository.loadTrips()).single;

      expect(loaded.alerts.single.isOpen, isTrue);
      expect(loaded.alerts.single.peakSpeed, 85,
          reason: 'peak defaults to the opening speed');
    });
  });

  group('enums stored by name', () {
    /// LocationType has already grown from six values to eight. Index-based
    /// storage survived only because the new members were appended; a reorder
    /// would silently rewrite every stored trip.
    test('a reordered enum does not corrupt stored trips', () async {
      await repository.saveTrip(trip());

      final db = await databaseFactoryFfi.openDatabase(
        '${tempDir.path}/trips.db',
        // Not singleInstance: otherwise sqflite hands back the repository's
        // own handle and closing this one closes that too.
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final rows = await db.query('trips', columns: ['location']);
      await db.close();

      expect(rows.single['location'], 'highway',
          reason: 'stored as a name, so index changes cannot reinterpret it');
    });

    test('an unknown enum name degrades instead of throwing', () async {
      final db = await databaseFactoryFfi.openDatabase(
        '${tempDir.path}/trips.db',
        options: OpenDatabaseOptions(readOnly: false, singleInstance: false),
      );
      await db.insert('trips', {
        'id': 'weird',
        'start_time': DateTime(2026, 7, 31).toIso8601String(),
        'location': 'a_class_that_no_longer_exists',
        'base_speed_limit': 60,
        'recommended_speed': 55,
        'avg_risk_score': 0,
        'distance_traveled_meters': 0,
      });
      await db.close();

      final loaded = await repository.loadTrips();

      expect(loaded.single.location, LocationType.urban);
    });
  });

  group('legacy migration', () {
    test('imports the old blob and keeps its counts', () async {
      final legacy = [
        trip(id: 'legacy1', overSpeedCount: 47),
        trip(id: 'legacy2', start: DateTime(2026, 6, 1), overSpeedCount: 3),
      ];

      final imported = await repository.migrateFromLegacy(() async => legacy);

      expect(imported, 2);
      final loaded = await repository.loadTrips();
      expect(loaded, hasLength(2));
      expect(
        loaded.firstWhere((t) => t.id == 'legacy1').overSpeedCount,
        47,
        reason: 'old inflated counts are carried as recorded, not invented anew',
      );
    });

    test('runs only once', () async {
      await repository.migrateFromLegacy(() async => [trip(id: 'legacy1')]);
      final second =
          await repository.migrateFromLegacy(() async => [trip(id: 'legacy2')]);

      expect(second, 0);
      expect(await repository.tripCount(), 1);
    });

    test('a corrupt blob does not block startup or retry forever', () async {
      final imported = await repository.migrateFromLegacy(
        () async => throw const FormatException('unparseable'),
      );

      expect(imported, 0);
      // Marked done, so the next launch does not retry a broken import.
      expect(await repository.migrateFromLegacy(() async => [trip()]), 0);
    });
  });

  group('housekeeping', () {
    test('deleting removes only the named trip', () async {
      await repository.saveTrip(trip(id: 'a'));
      await repository.saveTrip(trip(id: 'b', start: DateTime(2026, 6, 1)));

      await repository.deleteTrip('a');

      expect((await repository.loadTrips()).map((t) => t.id), ['b']);
    });

    test('clear empties the history', () async {
      await repository.saveTrip(trip(id: 'a'));
      await repository.saveTrip(trip(id: 'b', start: DateTime(2026, 6, 1)));

      await repository.clear();

      expect(await repository.loadTrips(), isEmpty);
    });

    test('a closed repository returns empty rather than throwing', () async {
      await repository.close();

      expect(await repository.loadTrips(), isEmpty);
      expect(await repository.recordsFor('t1'), isEmpty);
    });
  });
}
