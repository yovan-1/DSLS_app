import 'dart:io';

import 'package:dsls_app/models/speed_calculator.dart' show LocationType;
import 'package:dsls_app/models/speed_model/road_conditions.dart'
    show LimitSource;
import 'package:dsls_app/services/road_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs against the real shipped extract rather than a synthetic fixture.
/// sqflite has no implementation in the test VM, so the FFI factory stands in;
/// the SQL, the R-tree query and the geometry unpacking are the same either way.
///
/// Absolute, because the FFI factory resolves relative paths against its own
/// databases directory rather than the working directory.
final assetPath = '${Directory.current.path}/assets/roads.db';

void main() {
  late RoadDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = RoadDatabase();
    await database.openFile(
      assetPath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
  });

  tearDown(() async => database.close());

  group('provenance', () {
    /// The data this replaced had no source comment anywhere — nobody could
    /// tell how old it was or where it came from.
    test('records where the data came from and when', () {
      final meta = database.metadata;

      expect(meta['source'], contains('OpenStreetMap'));
      expect(meta['license'], contains('ODbL'));
      expect(meta['schema_version'], '1');
      expect(DateTime.parse(meta['built_utc']!).isAfter(DateTime(2026)), isTrue);
      expect(meta['bbox'], isNotEmpty);
    });

    test('records the fallback limits used for untagged ways', () {
      expect(database.metadata['fallback_limits'], contains('residential'));
      expect(database.metadata['highway_classes'], contains('trunk'));
    });

    test('carries a real number of roads', () {
      expect(int.parse(database.metadata['way_count']!), greaterThan(10000),
          reason: 'the hand-typed data this replaces had three road segments');
    });
  });

  group('matching', () {
    test('finds a road in central Mbarara', () async {
      final match = await database.nearestRoad(-0.6072, 30.6545,
          corridorMetres: 200);

      expect(match, isNotNull);
      expect(match!.distanceMetres, lessThanOrEqualTo(200));
      expect(match.speedLimitKph, greaterThan(0));
    });

    test('returns null well away from any mapped road', () async {
      // Middle of Lake Victoria, inside the extract box but not on a road.
      final match = await database.nearestRoad(-0.9, 31.15);

      expect(match, isNull,
          reason: 'better to say nothing than to present a guess as a match');
    });

    test('returns null outside the extract entirely', () async {
      final match = await database.nearestRoad(51.5074, -0.1278); // London

      expect(match, isNull);
    });

    test('respects the corridor width', () async {
      final wide = await database.nearestRoad(-0.6072, 30.6545,
          corridorMetres: 500);
      expect(wide, isNotNull);

      final narrow = await database.nearestRoad(
        -0.6072,
        30.6545,
        corridorMetres: 0.5,
      );
      // Either nothing, or something genuinely within half a metre.
      if (narrow != null) {
        expect(narrow.distanceMetres, lessThanOrEqualTo(0.5));
      }
    });

    test('is deterministic', () async {
      final results = <String>{};
      for (var i = 0; i < 10; i++) {
        final match =
            await database.nearestRoad(-0.6072, 30.6545, corridorMetres: 200);
        results.add('${match?.id}:${match?.speedLimitKph}');
      }

      expect(results, hasLength(1));
    });

    test('reports the nearest of several candidates', () async {
      // Any hit must be no further than the corridor allows, and taking a
      // wider corridor must not produce a further match.
      final tight =
          await database.nearestRoad(-0.6072, 30.6545, corridorMetres: 50);
      final loose =
          await database.nearestRoad(-0.6072, 30.6545, corridorMetres: 1000);

      expect(loose, isNotNull);
      if (tight != null) {
        expect(loose!.distanceMetres, lessThanOrEqualTo(tight.distanceMetres));
      }
    });
  });

  group('tag handling', () {
    test('a posted limit is distinguished from an inferred one', () async {
      final db = await databaseFactoryFfi.openDatabase(assetPath,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final posted = await db.rawQuery(
          "SELECT COUNT(*) c FROM roads WHERE limit_source = 'posted'");
      final inferred = await db.rawQuery(
          "SELECT COUNT(*) c FROM roads WHERE limit_source = 'inferred'");
      await db.close();

      expect(posted.first['c'], greaterThan(0));
      // Only ~1.6% of ways in Uganda carry maxspeed, so almost everything is
      // class-derived. The model applies its uncertainty margin to those.
      expect(inferred.first['c'], greaterThan(posted.first['c'] as int));
    });

    test('every row has a limit and a location type', () async {
      final db = await databaseFactoryFfi.openDatabase(assetPath,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final bad = await db.rawQuery(
        'SELECT COUNT(*) c FROM roads WHERE speed_limit IS NULL'
        ' OR speed_limit <= 0 OR location_type IS NULL',
      );
      await db.close();

      expect(bad.first['c'], 0);
    });

    test('location types are all real enum members', () async {
      final db = await databaseFactoryFfi.openDatabase(assetPath,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final rows =
          await db.rawQuery('SELECT DISTINCT location_type FROM roads');
      await db.close();

      final names = LocationType.values.map((v) => v.name).toSet();
      for (final row in rows) {
        expect(names, contains(row['location_type']));
      }
    });

    /// `lit` being null is meaningful: it means nobody surveyed it, which the
    /// sight-distance model treats differently from a known-unlit road.
    test('unsurveyed lighting stays unknown rather than becoming false',
        () async {
      final db = await databaseFactoryFfi.openDatabase(assetPath,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final nulls = await db
          .rawQuery('SELECT COUNT(*) c FROM roads WHERE lit IS NULL');
      final total = await db.rawQuery('SELECT COUNT(*) c FROM roads');
      await db.close();

      expect(nulls.first['c'], greaterThan(0));
      expect(nulls.first['c'], lessThan(total.first['c'] as int));
    });

    test('a match exposes lit and surface as nullable', () async {
      final match = await database.nearestRoad(-0.6072, 30.6545,
          corridorMetres: 500);

      expect(match, isNotNull);
      // Both may legitimately be null; the point is that they are typed that
      // way and the query does not invent values.
      expect(match!.isLit, anyOf(isNull, isA<bool>()));
      expect(match.surface, anyOf(isNull, isA<String>()));
      expect(match.limitSource,
          anyOf(LimitSource.posted, LimitSource.inferred));
    });
  });

  group('lifecycle', () {
    test('reports whether it is open', () async {
      expect(database.isOpen, isTrue);
      await database.close();
      expect(database.isOpen, isFalse);
    });

    test('a closed database returns no match rather than throwing', () async {
      await database.close();

      expect(await database.nearestRoad(-0.6072, 30.6545), isNull);
    });
  });
}
