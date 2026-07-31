import 'dart:convert';
import 'dart:io';

import 'package:dsls_app/models/speed_calculator.dart' show LocationType;
import 'package:dsls_app/models/speed_model/speed_recommendation.dart'
    show RiskBand;
import 'package:dsls_app/models/trip_data.dart';
import 'package:dsls_app/services/trip_export_service.dart';
import 'package:dsls_app/services/trip_repository.dart';
import 'package:dsls_app/services/trip_service.dart' show DrivingRecord;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

TripData trip({String id = 't1', DateTime? start}) => TripData(
      id: id,
      startTime: start ?? DateTime(2026, 7, 31, 8),
      endTime: (start ?? DateTime(2026, 7, 31, 8)).add(const Duration(hours: 1)),
      location: LocationType.highway,
      baseSpeedLimit: 80,
      recommendedSpeed: 70,
      maxSpeed: 95,
      avgSpeed: 62,
      overSpeedCount: 2,
      distanceTraveledMeters: 12345,
    );

DrivingRecord record(int i, {double? lat, double? lon}) => DrivingRecord(
      speed: 60 + i,
      recommendedSpeed: 70,
      riskBand: RiskBand.moderate,
      isOverSpeed: false,
      timestamp: DateTime(2026, 7, 31, 8, 0, i),
      latitude: lat,
      longitude: lon,
    );

void main() {
  late TripRepository repository;
  late TripExportService exporter;
  late Directory tempDir;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('trip_export_test');
    repository = TripRepository();
    await repository.open(
      factoryOverride: databaseFactoryFfi,
      path: '${tempDir.path}/trips.db',
    );
    exporter = TripExportService(repository: repository);
  });

  tearDown(() async {
    await repository.close();
    await tempDir.delete(recursive: true);
  });

  group('JSON export', () {
    test('round-trips the trip summary', () async {
      await repository.saveTrip(trip());

      final decoded = jsonDecode(await exporter.buildJson([trip()]))
          as Map<String, dynamic>;
      final exported = (decoded['trips'] as List).single as Map<String, dynamic>;

      expect(decoded['tripCount'], 1);
      expect(exported['id'], 't1');
      expect(exported['maxSpeed'], 95);
      expect(exported['distanceTraveledMeters'], 12345);
      // Enums by name, so the export does not depend on declaration order.
      expect(exported['location'], 'highway');
    });

    test('carries the recorded route', () async {
      await repository.saveTrip(trip(), records: [
        record(0, lat: -0.6072, lon: 30.6545),
        record(1, lat: -0.6062, lon: 30.6545),
      ]);

      final decoded =
          jsonDecode(await exporter.buildJson([trip()])) as Map<String, dynamic>;
      final route =
          ((decoded['trips'] as List).single as Map<String, dynamic>)['route']
              as List;

      expect(route, hasLength(2));
      expect((route.first as Map)['lat'], closeTo(-0.6072, 1e-6));
      expect((route.first as Map)['speed'], 60);
    });

    test('omits records with no fix from the route', () async {
      await repository.saveTrip(trip(), records: [
        record(0),
        record(1, lat: -0.6, lon: 30.6),
      ]);

      final decoded =
          jsonDecode(await exporter.buildJson([trip()])) as Map<String, dynamic>;
      final route =
          ((decoded['trips'] as List).single as Map<String, dynamic>)['route']
              as List;

      expect(route, hasLength(1));
    });

    test('stamps the schema version so an importer knows the shape', () async {
      final decoded =
          jsonDecode(await exporter.buildJson([])) as Map<String, dynamic>;

      expect(decoded['schemaVersion'], TripRepository.schemaVersion);
      expect(DateTime.parse(decoded['exportedAt'] as String), isNotNull);
    });

    test('handles no trips at all', () async {
      final decoded =
          jsonDecode(await exporter.buildJson([])) as Map<String, dynamic>;

      expect(decoded['tripCount'], 0);
      expect(decoded['trips'], isEmpty);
    });
  });

  group('CSV export', () {
    test('has a header and one row per driving record', () async {
      await repository.saveTrip(trip(), records: [
        record(0, lat: -0.6072, lon: 30.6545),
        record(1, lat: -0.6062, lon: 30.6545),
        record(2, lat: -0.6052, lon: 30.6545),
      ]);

      final lines = (await exporter.buildCsv([trip()])).trim().split('\n');

      expect(lines.first, startsWith('trip_id,timestamp,speed_kph'));
      expect(lines, hasLength(4), reason: 'header plus three records');
      expect(lines[1], contains('t1'));
      expect(lines[1], contains('-0.6072'));
    });

    test('leaves position columns empty when there was no fix', () async {
      await repository.saveTrip(trip(), records: [record(0)]);

      final lines = (await exporter.buildCsv([trip()])).trim().split('\n');

      expect(lines[1], endsWith(','),
          reason: 'trailing empty latitude and longitude fields');
    });

    test('is just a header when there are no records', () async {
      await repository.saveTrip(trip());

      final csv = await exporter.buildCsv([trip()]);

      expect(csv.trim().split('\n'), hasLength(1));
    });

    test('quotes a field containing a comma', () async {
      const awkward = 'trip,with,commas';
      await repository.saveTrip(trip(id: awkward), records: [record(0)]);

      final lines =
          (await exporter.buildCsv([trip(id: awkward)])).trim().split('\n');

      expect(lines[1], startsWith('"trip,with,commas"'));
    });
  });

  group('without a repository', () {
    test('still exports summaries, just no route', () async {
      const detached = TripExportService();

      final decoded =
          jsonDecode(await detached.buildJson([trip()])) as Map<String, dynamic>;
      final exported = (decoded['trips'] as List).single as Map<String, dynamic>;

      expect(exported['id'], 't1');
      expect(exported['route'], isEmpty);
    });
  });
}
