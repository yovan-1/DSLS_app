import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/speed_calculator.dart' show LocationType;
import '../models/speed_model/speed_recommendation.dart' show RiskBand;
import '../models/trip_data.dart';
import 'trip_service.dart' show DrivingRecord;

/// Persistent storage for trips, their per-second records and their alert
/// episodes.
///
/// Replaces a single JSON blob in SharedPreferences that was rewritten in full
/// on every mutation, with no size bound and no pruning — so every save and
/// every load was O(total history), and a failure was swallowed silently.
///
/// It also gives `DrivingRecord` somewhere to live. It had no `toJson` at all,
/// so the safe/moderate/risky percentages the history screen shows were
/// computed from an in-memory list that cleared on the next trip: every one of
/// those numbers was meaningless after an app restart.
class TripRepository {
  static const int schemaVersion = 1;
  static const String defaultFileName = 'trips.db';

  Database? _db;

  bool get isOpen => _db != null;

  /// [factoryOverride] and [path] let tests run against the FFI factory and a
  /// temporary file, since sqflite has no implementation in the test VM.
  Future<void> open({DatabaseFactory? factoryOverride, String? path}) async {
    if (_db != null) return;
    final factory = factoryOverride ?? databaseFactory;
    final target = path ?? '${await factory.getDatabasesPath()}/$defaultFileName';

    _db = await factory.openDatabase(
      target,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          for (final statement in _schema) {
            await db.execute(statement);
          }
        },
        onUpgrade: (db, from, to) async {
          // Nothing to migrate yet. The version column exists so the next
          // schema change has somewhere to hook in rather than needing a
          // wipe — the JSON blob this replaces had no version at all.
          debugPrint('[TripRepository] Schema $from -> $to');
        },
      ),
    );
  }

  static const List<String> _schema = [
    '''
    CREATE TABLE trips (
      id TEXT PRIMARY KEY,
      start_time TEXT NOT NULL,
      end_time TEXT,
      location TEXT NOT NULL,
      base_speed_limit INTEGER NOT NULL,
      recommended_speed INTEGER NOT NULL,
      max_speed INTEGER NOT NULL DEFAULT 0,
      avg_speed INTEGER NOT NULL DEFAULT 0,
      over_speed_count INTEGER NOT NULL DEFAULT 0,
      road_segment_id TEXT,
      actual_speed_limit INTEGER,
      estimated_surface TEXT,
      avg_risk_score REAL NOT NULL DEFAULT 0,
      distance_traveled_meters INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE driving_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      timestamp TEXT NOT NULL,
      speed INTEGER NOT NULL,
      recommended_speed INTEGER NOT NULL,
      risk_band TEXT NOT NULL,
      is_over_speed INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_records_trip ON driving_records(trip_id)',
    '''
    CREATE TABLE alert_episodes (
      id TEXT PRIMARY KEY,
      trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      type TEXT NOT NULL,
      started_at TEXT NOT NULL,
      ended_at TEXT,
      speed INTEGER NOT NULL,
      peak_speed INTEGER NOT NULL,
      recommended_speed INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_alerts_trip ON alert_episodes(trip_id)',
    'CREATE TABLE settings_kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  ];

  Future<List<TripData>> loadTrips() async {
    final db = _db;
    if (db == null) return const [];

    final tripRows = await db.query('trips', orderBy: 'start_time DESC');
    if (tripRows.isEmpty) return const [];

    final alertRows = await db.query('alert_episodes', orderBy: 'started_at');
    final alertsByTrip = <String, List<SpeedAlert>>{};
    for (final row in alertRows) {
      alertsByTrip
          .putIfAbsent(row['trip_id'] as String, () => [])
          .add(_alertFromRow(row));
    }

    return tripRows
        .map((row) => _tripFromRow(row, alertsByTrip[row['id']] ?? const []))
        .toList();
  }

  /// Writes a trip and everything belonging to it in one transaction, so a
  /// crash mid-save cannot leave records orphaned from their trip.
  Future<void> saveTrip(
    TripData trip, {
    List<DrivingRecord> records = const [],
  }) async {
    final db = _db;
    if (db == null) return;

    await db.transaction((txn) async {
      await txn.insert(
        'trips',
        _tripToRow(trip),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Replace rather than append, so re-saving a trip is idempotent.
      await txn.delete('driving_records',
          where: 'trip_id = ?', whereArgs: [trip.id]);
      await txn
          .delete('alert_episodes', where: 'trip_id = ?', whereArgs: [trip.id]);

      final batch = txn.batch();
      for (final record in records) {
        batch.insert('driving_records', {
          'trip_id': trip.id,
          'timestamp': record.timestamp.toIso8601String(),
          'speed': record.speed,
          'recommended_speed': record.recommendedSpeed,
          'risk_band': record.riskBand.name,
          'is_over_speed': record.isOverSpeed ? 1 : 0,
        });
      }
      for (final alert in trip.alerts) {
        batch.insert('alert_episodes', {
          'id': alert.id,
          'trip_id': trip.id,
          'type': alert.type.name,
          'started_at': alert.time.toIso8601String(),
          'ended_at': alert.endTime?.toIso8601String(),
          'speed': alert.speed,
          'peak_speed': alert.peakSpeed,
          'recommended_speed': alert.recommendedSpeed,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// The per-second samples for a trip. These survive a restart now, which is
  /// what makes the behaviour percentages mean anything.
  Future<List<DrivingRecord>> recordsFor(String tripId) async {
    final db = _db;
    if (db == null) return const [];

    final rows = await db.query(
      'driving_records',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'timestamp',
    );

    return rows
        .map((row) => DrivingRecord(
              speed: row['speed'] as int,
              recommendedSpeed: row['recommended_speed'] as int,
              riskBand: _riskBandFrom(row['risk_band'] as String),
              isOverSpeed: (row['is_over_speed'] as int) == 1,
              timestamp: DateTime.parse(row['timestamp'] as String),
            ))
        .toList();
  }

  Future<void> deleteTrip(String id) async {
    // ON DELETE CASCADE takes the records and episodes with it.
    await _db?.delete('trips', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clear() async {
    await _db?.delete('trips');
  }

  Future<int> tripCount() async {
    final db = _db;
    if (db == null) return 0;
    final rows = await db.rawQuery('SELECT COUNT(*) c FROM trips');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// One-shot import of the trips held in the old SharedPreferences blob.
  ///
  /// Counts are carried across exactly as recorded. Trips logged before the
  /// per-episode fix have inflated alert counts, but rewriting them would
  /// invent history the app never observed — pilot testers see the numbers
  /// they were shown at the time.
  ///
  /// Returns the number of trips imported. Idempotent: it records that it ran
  /// and does nothing on subsequent calls.
  Future<int> migrateFromLegacy(
    Future<List<TripData>> Function() readLegacyTrips,
  ) async {
    final db = _db;
    if (db == null) return 0;

    final done = await db.query('settings_kv',
        where: 'key = ?', whereArgs: [_migrationKey]);
    if (done.isNotEmpty) return 0;

    var imported = 0;
    try {
      final legacy = await readLegacyTrips();
      for (final trip in legacy) {
        await saveTrip(trip);
        imported++;
      }
    } catch (e) {
      debugPrint('[TripRepository] Legacy migration failed: $e');
      // Deliberately still marked done: a blob that cannot be parsed will not
      // parse on the next launch either, and retrying forever would re-run a
      // partial import each time.
    }

    await db.insert(
      'settings_kv',
      {'key': _migrationKey, 'value': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('[TripRepository] Migrated $imported legacy trips');
    return imported;
  }

  static const String _migrationKey = 'legacy_trips_migrated_at';

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Map<String, Object?> _tripToRow(TripData trip) => {
        'id': trip.id,
        'start_time': trip.startTime.toIso8601String(),
        'end_time': trip.endTime?.toIso8601String(),
        // Enums by name throughout: LocationType has already grown from six
        // members to eight, and index-based storage only survived that by luck.
        'location': trip.location.name,
        'base_speed_limit': trip.baseSpeedLimit,
        'recommended_speed': trip.recommendedSpeed,
        'max_speed': trip.maxSpeed,
        'avg_speed': trip.avgSpeed,
        'over_speed_count': trip.overSpeedCount,
        'road_segment_id': trip.roadSegmentId,
        'actual_speed_limit': trip.actualSpeedLimit,
        'estimated_surface': trip.estimatedSurface,
        'avg_risk_score': trip.avgRiskScore,
        'distance_traveled_meters': trip.distanceTraveledMeters,
      };

  static TripData _tripFromRow(
    Map<String, Object?> row,
    List<SpeedAlert> alerts,
  ) =>
      TripData(
        id: row['id'] as String,
        startTime: DateTime.parse(row['start_time'] as String),
        endTime: row['end_time'] == null
            ? null
            : DateTime.parse(row['end_time'] as String),
        location: _locationTypeFrom(row['location'] as String),
        baseSpeedLimit: row['base_speed_limit'] as int,
        recommendedSpeed: row['recommended_speed'] as int,
        maxSpeed: row['max_speed'] as int,
        avgSpeed: row['avg_speed'] as int,
        overSpeedCount: row['over_speed_count'] as int,
        alerts: alerts,
        roadSegmentId: row['road_segment_id'] as String?,
        actualSpeedLimit: row['actual_speed_limit'] as int?,
        estimatedSurface: row['estimated_surface'] as String?,
        avgRiskScore: (row['avg_risk_score'] as num).toDouble(),
        distanceTraveledMeters: row['distance_traveled_meters'] as int,
      );

  static SpeedAlert _alertFromRow(Map<String, Object?> row) => SpeedAlert(
        id: row['id'] as String,
        time: DateTime.parse(row['started_at'] as String),
        endTime: row['ended_at'] == null
            ? null
            : DateTime.parse(row['ended_at'] as String),
        speed: row['speed'] as int,
        peakSpeed: row['peak_speed'] as int,
        recommendedSpeed: row['recommended_speed'] as int,
        type: AlertType.values.firstWhere(
          (v) => v.name == row['type'],
          orElse: () => AlertType.overSpeed,
        ),
      );

  static LocationType _locationTypeFrom(String name) =>
      LocationType.values.firstWhere(
        (v) => v.name == name,
        orElse: () => LocationType.urban,
      );

  static RiskBand _riskBandFrom(String name) => RiskBand.values.firstWhere(
        (v) => v.name == name,
        orElse: () => RiskBand.low,
      );
}
