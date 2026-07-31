import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/road_segment.dart';
import '../models/speed_calculator.dart' show LocationType;
import '../models/speed_model/road_conditions.dart' show LimitSource;

/// A road from the offline database, with how far it is from the query point.
@immutable
class RoadMatch {
  final int id;
  final String? name;
  final LocationType locationType;
  final int speedLimitKph;
  final LimitSource limitSource;

  /// OSM `lit`. Null means *not surveyed*, which is not the same as unlit —
  /// only 0.8% of ways in the shipped extract carry the tag, so this is
  /// usually null and the sight-distance model keeps its unknown-lighting
  /// fallback.
  final bool? isLit;

  /// OSM `surface`, e.g. `asphalt`, `unpaved`, `dirt`. Null when not surveyed.
  final String? surface;

  final double distanceMetres;

  const RoadMatch({
    required this.id,
    required this.name,
    required this.locationType,
    required this.speedLimitKph,
    required this.limitSource,
    required this.isLit,
    required this.surface,
    required this.distanceMetres,
  });

  /// True when the limit came from an OSM `maxspeed` tag rather than being
  /// derived from the road class.
  bool get isPosted => limitSource == LimitSource.posted;
}

/// Reads the offline road database shipped as an app asset.
///
/// Replaces three hand-typed road segments — one of which approximated ~90 km
/// of highway with four points, none of which carried any provenance — with
/// ~14.8k OpenStreetMap ways for the Mbarara region.
///
/// Queries are local. The app never talks to a map service while driving: a
/// speed advisory cannot depend on the network for its ceiling.
///
/// Lookups go through an R-tree over way bounding boxes to get candidates, then
/// refine by true point-to-polyline distance. Geometry is stored per way as
/// packed float32 pairs rather than one row per node pair — the extract has
/// ~458k segments but only ~14.8k ways, and float32 resolves to about a metre,
/// well inside GPS error.
class RoadDatabase {
  static const String assetPath = 'assets/roads.db';
  static const String versionAssetPath = 'assets/roads.db.version';
  static const String _fileName = 'roads.db';
  static const String _versionFileName = 'roads.db.version';

  /// How far off a way's centreline a fix can be and still count as on it.
  /// Covers GPS error plus half a carriageway; OSM ways carry no width.
  static const double defaultCorridorMetres = 25;

  Database? _db;
  Map<String, String> _meta = const {};

  bool get isOpen => _db != null;

  /// Provenance of the loaded extract: source, licence, build date, bounding
  /// box and the fallback limit table used. The data this replaced had none.
  Map<String, String> get metadata => Map.unmodifiable(_meta);

  /// Opens the database, copying it out of the bundle on first run or whenever
  /// the bundled version stamp differs from the copy on disk.
  ///
  /// [databaseFactoryOverride] and [directoryOverride] exist so tests can run
  /// against a temporary file with the FFI factory, since sqflite has no
  /// implementation in the plain test VM.
  Future<void> open({
    DatabaseFactory? databaseFactoryOverride,
    Directory? directoryOverride,
  }) async {
    if (_db != null) return;

    final factory = databaseFactoryOverride ?? databaseFactory;
    final directory =
        directoryOverride ?? await getApplicationDocumentsDirectory();
    final target = File('${directory.path}/$_fileName');

    await _copyIfStale(target, directory);

    _db = await factory.openDatabase(
      target.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: true),
    );
    await _loadMeta();
  }

  /// Opens an existing file directly, skipping the asset copy. For tests and
  /// for tooling that builds a database in place.
  Future<void> openFile(
    String path, {
    DatabaseFactory? databaseFactoryOverride,
  }) async {
    if (_db != null) return;
    final factory = databaseFactoryOverride ?? databaseFactory;
    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: true),
    );
    await _loadMeta();
  }

  Future<void> _copyIfStale(File target, Directory directory) async {
    final stampFile = File('${directory.path}/$_versionFileName');

    String? bundledStamp;
    try {
      bundledStamp = (await rootBundle.loadString(versionAssetPath)).trim();
    } catch (_) {
      // No stamp shipped; fall back to "copy only if missing".
    }

    if (await target.exists()) {
      if (bundledStamp == null) return;
      if (await stampFile.exists()) {
        final onDisk = (await stampFile.readAsString()).trim();
        if (onDisk == bundledStamp) return;
      }
    }

    final data = await rootBundle.load(assetPath);
    await target.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    if (bundledStamp != null) {
      await stampFile.writeAsString(bundledStamp, flush: true);
    }
    if (kDebugMode) {
      debugPrint('[RoadDatabase] Installed road database ($bundledStamp)');
    }
  }

  Future<void> _loadMeta() async {
    try {
      final rows = await _db!.query('meta');
      _meta = {
        for (final row in rows) row['key'] as String: row['value'] as String,
      };
    } catch (e) {
      debugPrint('[RoadDatabase] Could not read meta: $e');
      _meta = const {};
    }
  }

  /// The nearest road whose centreline passes within [corridorMetres].
  ///
  /// Returns null when the fix is not on any mapped road, so the caller can say
  /// so rather than presenting a fallback as a match.
  Future<RoadMatch?> nearestRoad(
    double lat,
    double lon, {
    double corridorMetres = defaultCorridorMetres,
  }) async {
    final db = _db;
    if (db == null) return null;

    // Pad the R-tree window by the corridor, converted to degrees. Longitude
    // degrees shrink with latitude, so scale by cos(lat).
    final latPad = corridorMetres / 111194.0;
    final cosLat = _cosDegrees(lat).abs();
    final lonPad = cosLat < 1e-6 ? 180.0 : latPad / cosLat;

    final rows = await db.rawQuery(
      'SELECT r.id, r.name, r.location_type, r.speed_limit, r.limit_source,'
      ' r.lit, r.surface, r.geometry'
      ' FROM road_rtree t JOIN roads r ON r.id = t.id'
      ' WHERE t.max_lat >= ? AND t.min_lat <= ?'
      '   AND t.max_lon >= ? AND t.min_lon <= ?',
      [lat - latPad, lat + latPad, lon - lonPad, lon + lonPad],
    );

    RoadMatch? best;
    for (final row in rows) {
      final geometry = _unpackGeometry(row['geometry'] as Uint8List);
      if (geometry.length < 2) continue;

      final distance = _distanceToPolyline(lat, lon, geometry);
      if (distance > corridorMetres) continue;
      if (best != null && distance >= best.distanceMetres) continue;

      final litRaw = row['lit'] as int?;
      best = RoadMatch(
        id: row['id'] as int,
        name: row['name'] as String?,
        locationType: _locationTypeFrom(row['location_type'] as String),
        speedLimitKph: row['speed_limit'] as int,
        limitSource: row['limit_source'] == 'posted'
            ? LimitSource.posted
            : LimitSource.inferred,
        isLit: litRaw == null ? null : litRaw == 1,
        surface: row['surface'] as String?,
        distanceMetres: distance,
      );
    }
    return best;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _meta = const {};
  }

  static double _distanceToPolyline(
    double lat,
    double lon,
    List<double> geometry,
  ) {
    var best = double.infinity;
    for (var i = 0; i + 3 < geometry.length; i += 2) {
      final d = LocationUtils.pointToLineSegmentDistance(
        lat,
        lon,
        geometry[i],
        geometry[i + 1],
        geometry[i + 2],
        geometry[i + 3],
      );
      if (d < best) best = d;
    }
    return best;
  }

  /// Packed little-endian float32 lat/lon pairs, flattened.
  static List<double> _unpackGeometry(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    final count = bytes.lengthInBytes ~/ 4;
    return List<double>.generate(
      count,
      (i) => view.getFloat32(i * 4, Endian.little),
      growable: false,
    );
  }

  static LocationType _locationTypeFrom(String name) =>
      LocationType.values.firstWhere(
        (v) => v.name == name,
        orElse: () => LocationType.urban,
      );

  static double _cosDegrees(double degrees) => math.cos(degrees * math.pi / 180);
}
