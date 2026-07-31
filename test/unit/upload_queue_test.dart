import 'dart:io';

import 'package:dsls_app/models/speed_calculator.dart' show LocationType;
import 'package:dsls_app/models/speed_model/speed_recommendation.dart'
    show RiskBand;
import 'package:dsls_app/models/trip_data.dart';
import 'package:dsls_app/services/trip_repository.dart';
import 'package:dsls_app/services/trip_service.dart' show DrivingRecord;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

TripData trip({String id = 't1', DateTime? start}) => TripData(
      id: id,
      startTime: start ?? DateTime(2026, 7, 31, 8),
      endTime: (start ?? DateTime(2026, 7, 31, 8)).add(const Duration(hours: 1)),
      location: LocationType.urban,
      baseSpeedLimit: 60,
      recommendedSpeed: 50,
    );

void main() {
  late TripRepository repository;
  late Directory tempDir;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('upload_queue_test');
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

  group('the queue', () {
    /// It used to be an in-memory list nothing ever wrote to, drained by a
    /// method nothing ever called, emptied on every restart.
    test('holds a trip until it is dequeued', () async {
      await repository.saveTrip(trip());

      await repository.enqueueUpload('t1');

      expect(await repository.pendingUploadCount(), 1);
      expect((await repository.pendingUploads()).single.tripId, 't1');
    });

    test('enqueueing twice does not duplicate', () async {
      await repository.saveTrip(trip());

      await repository.enqueueUpload('t1');
      await repository.enqueueUpload('t1');

      expect(await repository.pendingUploadCount(), 1);
    });

    test('survives a reopen', () async {
      await repository.saveTrip(trip());
      await repository.enqueueUpload('t1');
      await repository.close();

      final reopened = TripRepository();
      await reopened.open(
        factoryOverride: databaseFactoryFfi,
        path: '${tempDir.path}/trips.db',
      );
      addTearDown(reopened.close);

      expect(await reopened.pendingUploadCount(), 1,
          reason: 'a queue that empties on restart is not a queue');
    });

    test('dequeue removes it', () async {
      await repository.saveTrip(trip());
      await repository.enqueueUpload('t1');

      await repository.dequeueUpload('t1');

      expect(await repository.pendingUploadCount(), 0);
    });

    test('deleting the trip takes its queue entry', () async {
      await repository.saveTrip(trip());
      await repository.enqueueUpload('t1');

      await repository.deleteTrip('t1');

      expect(await repository.pendingUploadCount(), 0,
          reason: 'the foreign key cascade should take it');
    });

    test('returns entries oldest first', () async {
      await repository.saveTrip(trip(id: 'a'));
      await repository.saveTrip(trip(id: 'b', start: DateTime(2026, 6, 1)));

      await repository.enqueueUpload('a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repository.enqueueUpload('b');

      expect((await repository.pendingUploads()).map((q) => q.tripId),
          ['a', 'b']);
    });
  });

  group('bounded retry', () {
    test('records the failure reason and counts the attempt', () async {
      await repository.saveTrip(trip());
      await repository.enqueueUpload('t1');

      await repository.recordUploadFailure('t1', 'S3 403 AccessDenied');

      final queued = (await repository.pendingUploads()).single;
      expect(queued.attempts, 1);
      expect(queued.lastError, 'S3 403 AccessDenied');
    });

    /// Without a cap a trip S3 will never accept is retried on every launch
    /// and every network change, for ever.
    test('stops being offered once the attempt cap is reached', () async {
      await repository.saveTrip(trip());
      await repository.enqueueUpload('t1');

      for (var i = 0; i < 5; i++) {
        await repository.recordUploadFailure('t1', 'nope');
      }

      expect(await repository.pendingUploads(maxAttempts: 5), isEmpty);
      expect(await repository.pendingUploadCount(), 1,
          reason: 'it is still queued, just no longer retried');
    });

    test('is still offered below the cap', () async {
      await repository.saveTrip(trip());
      await repository.enqueueUpload('t1');
      await repository.recordUploadFailure('t1', 'nope');

      expect(await repository.pendingUploads(maxAttempts: 5), hasLength(1));
    });
  });

  group('upload history', () {
    test('records successes and failures', () async {
      await repository.saveTrip(trip());

      await repository.addUploadHistory('t1', succeeded: true);
      await repository.addUploadHistory('t1',
          succeeded: false, detail: 'S3 500');

      final history = await repository.uploadHistory();
      expect(history, hasLength(2));
      expect(history.any((e) => e.succeeded), isTrue);
      expect(history.firstWhere((e) => !e.succeeded).detail, 'S3 500');
    });

    test('survives a reopen', () async {
      await repository.saveTrip(trip());
      await repository.addUploadHistory('t1', succeeded: true);
      await repository.close();

      final reopened = TripRepository();
      await reopened.open(
        factoryOverride: databaseFactoryFfi,
        path: '${tempDir.path}/trips.db',
      );
      addTearDown(reopened.close);

      expect(await reopened.uploadHistory(), hasLength(1));
    });

    test('is capped so it cannot grow without bound', () async {
      await repository.saveTrip(trip());

      for (var i = 0; i < 60; i++) {
        await repository.addUploadHistory('t1', succeeded: true);
      }

      expect((await repository.uploadHistory()).length, lessThanOrEqualTo(50));
    });
  });

  group('recorded route', () {
    /// The app advertised uploading a "GPS route path" it had never recorded:
    /// driving records were sampled once a second but carried no position.
    test('comes back from the driving records', () async {
      final records = [
        for (var i = 0; i < 3; i++)
          DrivingRecord(
            speed: 40,
            recommendedSpeed: 50,
            riskBand: RiskBand.low,
            isOverSpeed: false,
            timestamp: DateTime(2026, 7, 31, 8, 0, i),
            latitude: -0.6072 + i * 0.001,
            longitude: 30.6545,
          ),
      ];

      await repository.saveTrip(trip(), records: records);
      final route = await repository.routeFor('t1');

      expect(route, hasLength(3));
      expect(route.first.latitude, closeTo(-0.6072, 1e-9));
      expect(route.last.latitude, closeTo(-0.6052, 1e-9));
    });

    test('skips records with no fix', () async {
      await repository.saveTrip(trip(), records: [
        DrivingRecord(
          speed: 40,
          recommendedSpeed: 50,
          riskBand: RiskBand.low,
          isOverSpeed: false,
          timestamp: DateTime(2026, 7, 31, 8),
        ),
        DrivingRecord(
          speed: 41,
          recommendedSpeed: 50,
          riskBand: RiskBand.low,
          isOverSpeed: false,
          timestamp: DateTime(2026, 7, 31, 8, 0, 1),
          latitude: -0.6,
          longitude: 30.6,
        ),
      ]);

      expect(await repository.routeFor('t1'), hasLength(1));
    });

    test('is empty for a trip recorded before positions were stored', () async {
      await repository.saveTrip(trip());

      expect(await repository.routeFor('t1'), isEmpty);
    });

    test('records round-trip their position', () async {
      await repository.saveTrip(trip(), records: [
        DrivingRecord(
          speed: 40,
          recommendedSpeed: 50,
          riskBand: RiskBand.low,
          isOverSpeed: false,
          timestamp: DateTime(2026, 7, 31, 8),
          latitude: -0.6072,
          longitude: 30.6545,
        ),
      ]);

      final loaded = (await repository.recordsFor('t1')).single;
      expect(loaded.hasPosition, isTrue);
      expect(loaded.latitude, closeTo(-0.6072, 1e-9));
      expect(loaded.longitude, closeTo(30.6545, 1e-9));
    });
  });
}
