import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trip_data.dart';
import 'trip_repository.dart';
import 'trip_service.dart' show DrivingRecord;

/// Gets trip data off the device without a cloud account.
///
/// The S3 path needs an AWS key typed into the phone; a researcher collecting
/// pilot data usually just wants the file. This writes it and hands it to the
/// system share sheet, so it can go out over email, Drive, Bluetooth or a USB
/// copy — whatever is already in use — and it works with no network at all.
class TripExportService {
  final TripRepository? _repository;

  const TripExportService({TripRepository? repository})
      : _repository = repository;

  /// Everything about a set of trips, including their recorded route.
  ///
  /// Structured rather than flat because a trip has one row of summary and
  /// hundreds of samples; a single CSV would either repeat the summary on every
  /// line or lose it.
  Future<String> buildJson(List<TripData> trips) async {
    final payload = <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      'schemaVersion': TripRepository.schemaVersion,
      'tripCount': trips.length,
      'trips': [
        for (final trip in trips)
          {
            ...trip.toJson(),
            'route': (await _recordsFor(trip.id))
                .where((r) => r.hasPosition)
                .map((r) => {
                      'at': r.timestamp.toIso8601String(),
                      'lat': r.latitude,
                      'lon': r.longitude,
                      'speed': r.speed,
                    })
                .toList(),
          },
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// One row per driving record, for anything that reads spreadsheets.
  Future<String> buildCsv(List<TripData> trips) async {
    final buffer = StringBuffer()
      ..writeln('trip_id,timestamp,speed_kph,recommended_kph,risk_band,'
          'is_over_speed,latitude,longitude');

    for (final trip in trips) {
      for (final record in await _recordsFor(trip.id)) {
        buffer.writeln([
          _csvField(trip.id),
          record.timestamp.toIso8601String(),
          record.speed,
          record.recommendedSpeed,
          record.riskBand.name,
          record.isOverSpeed,
          record.latitude ?? '',
          record.longitude ?? '',
        ].join(','));
      }
    }

    return buffer.toString();
  }

  /// Writes both files and opens the share sheet.
  ///
  /// Returns false when there is nothing to export, so the caller can say so
  /// rather than opening an empty share sheet.
  Future<bool> shareTrips(List<TripData> trips) async {
    if (trips.isEmpty) return false;

    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');

    final jsonFile = File('${directory.path}/dsls-trips-$stamp.json');
    await jsonFile.writeAsString(await buildJson(trips), flush: true);

    final csvFile = File('${directory.path}/dsls-records-$stamp.csv');
    await csvFile.writeAsString(await buildCsv(trips), flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(jsonFile.path), XFile(csvFile.path)],
        subject: 'DSLS trip data (${trips.length} trip'
            '${trips.length == 1 ? '' : 's'})',
      ),
    );
    return true;
  }

  Future<List<DrivingRecord>> _recordsFor(String tripId) async {
    final repository = _repository;
    if (repository == null) return const [];
    try {
      return await repository.recordsFor(tripId);
    } catch (e) {
      debugPrint('[TripExport] Could not read records for $tripId: $e');
      return const [];
    }
  }

  /// Quotes a field only when it needs it, per RFC 4180.
  static String _csvField(String value) {
    if (!value.contains(RegExp(r'[",\n\r]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
