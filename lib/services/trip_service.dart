import 'dart:async';
import 'package:flutter/material.dart' hide DayPeriod;
import '../models/trip_data.dart';
import '../models/speed_model/road_conditions.dart';
import '../models/speed_model/speed_advisor.dart';
import '../models/speed_model/speed_recommendation.dart';
import 'offline_storage_service.dart';
import 'cloud_upload_service.dart';
import 'settings_service.dart';
import 'trip_repository.dart';

class DrivingRecord {
  final int speed;
  final int recommendedSpeed;
  final RiskBand riskBand;
  final bool isOverSpeed;
  final DateTime timestamp;

  DrivingRecord({
    required this.speed,
    required this.recommendedSpeed,
    required this.riskBand,
    required this.isOverSpeed,
    required this.timestamp,
  });

  /// True when conditions alone put this sample in a dangerous band, before
  /// considering what the driver did about it.
  bool get isHighRisk =>
      riskBand == RiskBand.high || riskBand == RiskBand.severe;
}

class TripService extends ChangeNotifier {
  List<TripData> _trips = [];
  TripData? _currentTrip;
  bool _isTracking = false;
  OfflineStorageService? _storage;
  CloudUploadService? _cloudUploadService;
  SettingsService? _settingsService;
  TripRepository? _repository;

  final List<DrivingRecord> _drivingRecords = [];
  Timer? _recordingTimer;

  List<TripData> get trips => _trips;
  TripData? get currentTrip => _currentTrip;
  bool get isTracking => _isTracking;

  void setStorage(OfflineStorageService storage) {
    _storage = storage;
  }

  void setCloudUploadService(CloudUploadService service) {
    _cloudUploadService = service;
  }

  void setSettingsService(SettingsService service) {
    _settingsService = service;
  }

  /// Once a repository is attached it becomes the source of truth;
  /// [OfflineStorageService] is kept only as the migration source and as a
  /// fallback if the database could not be opened.
  void setRepository(TripRepository repository) {
    _repository = repository;
  }

  Future<void> loadTrips() async {
    if (_repository != null) {
      // One-shot import of the old SharedPreferences blob, so pilot testers
      // keep their history. Counts come across exactly as recorded.
      final storage = _storage;
      if (storage != null) {
        await _repository!.migrateFromLegacy(storage.getTrips);
      }
      _trips = await _repository!.loadTrips();
      notifyListeners();
      return;
    }

    if (_storage != null) {
      _trips = await _storage!.getTrips();
      notifyListeners();
    }
  }

  /// The per-second samples recorded for a past trip. Before these were
  /// persisted, the behaviour percentages were computed from an in-memory list
  /// that cleared on the next trip.
  Future<List<DrivingRecord>> recordsFor(String tripId) async =>
      _repository?.recordsFor(tripId) ?? Future.value(const []);

  List<DrivingRecord> get drivingRecords => _drivingRecords;
  int get recordCount => _drivingRecords.length;

  int get safeDrivingPercent {
    if (_drivingRecords.isEmpty) return 0;
    int safeCount =
        _drivingRecords
            .where((r) => r.isOverSpeed == false && !r.isHighRisk)
            .length;
    return ((safeCount / _drivingRecords.length) * 100).round();
  }

  int get moderateDrivingPercent {
    if (_drivingRecords.isEmpty) return 0;
    int modCount =
        _drivingRecords.where((r) {
          if (r.isOverSpeed && !r.isHighRisk) return true;
          if (!r.isOverSpeed && r.riskBand == RiskBand.moderate) return true;
          return false;
        }).length;
    return ((modCount / _drivingRecords.length) * 100).round();
  }

  int get riskyDrivingPercent {
    if (_drivingRecords.isEmpty) return 0;
    int riskyCount =
        _drivingRecords
            .where(
              (r) =>
                  r.isHighRisk ||
                  (r.isOverSpeed && (r.speed - r.recommendedSpeed) > 20),
            )
            .length;
    return ((riskyCount / _drivingRecords.length) * 100).round();
  }

  List<TripData> get recentTrips {
    final sorted = List<TripData>.from(_trips);
    sorted.sort((a, b) => b.startTime.compareTo(a.startTime));
    return sorted.take(10).toList();
  }

  List<TripData> get todayTrips {
    final now = DateTime.now();
    return _trips
        .where(
          (t) =>
              t.startTime.year == now.year &&
              t.startTime.month == now.month &&
              t.startTime.day == now.day,
        )
        .toList();
  }

  DrivingScore get drivingScore => DrivingScore.calculate(_trips);

  int get totalTrips => _trips.length;

  /// Total distance driven, in kilometres.
  ///
  /// Uses the distance actually integrated from GPS fixes during the trip.
  /// Trips recorded before that field was written fall back to
  /// `duration x avgSpeed`, which is what every trip used to use — an estimate
  /// that ignores stops and treats the average as if it were held throughout.
  int get totalDistance {
    var total = 0;
    for (final trip in _trips) {
      if (trip.distanceTraveledMeters > 0) {
        total += (trip.distanceTraveledMeters / 1000).round();
        continue;
      }
      final duration = trip.duration;
      if (duration != null) {
        total += (duration.inMinutes * trip.avgSpeed / 60).round();
      }
    }
    return total;
  }

  double get averageSpeed {
    if (_trips.isEmpty) return 0;
    int total = 0;
    int count = 0;
    for (final trip in _trips) {
      if (trip.avgSpeed > 0) {
        total += trip.avgSpeed;
        count++;
      }
    }
    return count > 0 ? total / count : 0;
  }

  List<TripData> get weekTrips {
    final now = DateTime.now();
    final weekAgo = now.subtract(Duration(days: 7));
    return _trips.where((t) => t.startTime.isAfter(weekAgo)).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  List<TripData> get monthTrips {
    final now = DateTime.now();
    final monthAgo = now.subtract(Duration(days: 30));
    return _trips.where((t) => t.startTime.isAfter(monthAgo)).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  Map<String, dynamic> get weeklySummary {
    final trips = weekTrips;
    if (trips.isEmpty) {
      return {'trips': 0, 'distance': 0, 'avgSpeed': 0, 'overspeed': 0};
    }
    int distance = 0;
    int totalSpeed = 0;
    int overspeed = 0;
    for (final trip in trips) {
      distance += (trip.duration?.inMinutes ?? 0) * trip.avgSpeed ~/ 60;
      totalSpeed += trip.avgSpeed;
      overspeed += trip.overSpeedCount;
    }
    return {
      'trips': trips.length,
      'distance': distance,
      'avgSpeed': trips.isNotEmpty ? totalSpeed ~/ trips.length : 0,
      'overspeed': overspeed,
    };
  }

  Map<String, dynamic> get monthlySummary {
    final trips = monthTrips;
    if (trips.isEmpty) {
      return {'trips': 0, 'distance': 0, 'avgSpeed': 0, 'overspeed': 0};
    }
    int distance = 0;
    int totalSpeed = 0;
    int overspeed = 0;
    for (final trip in trips) {
      distance += (trip.duration?.inMinutes ?? 0) * trip.avgSpeed ~/ 60;
      totalSpeed += trip.avgSpeed;
      overspeed += trip.overSpeedCount;
    }
    return {
      'trips': trips.length,
      'distance': distance,
      'avgSpeed': trips.isNotEmpty ? totalSpeed ~/ trips.length : 0,
      'overspeed': overspeed,
    };
  }

  void startTrip(RoadConditions conditions) {
    _drivingRecords.clear();
    _speedSum = 0;
    _distanceMetres = 0;
    _riskSum = 0;
    final recommendation = SpeedAdvisor.evaluate(conditions);
    _currentTrip = TripData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now(),
      location: conditions.roadClass,
      baseSpeedLimit: conditions.speedLimitKph,
      recommendedSpeed: recommendation.recommendedSpeedKph,
    );
    _isTracking = true;
    notifyListeners();
  }

  // Running totals, so the per-record update is O(1). `avgSpeed` used to refold
  // the entire record list on every append, which is O(n^2) over a trip — about
  // 26 million additions across a two-hour drive.
  int _speedSum = 0;
  double _distanceMetres = 0;
  int _riskSum = 0;

  /// Metres travelled so far, integrated from the fixes reported by the
  /// coordinator. Replaces deriving distance from `duration x avgSpeed`.
  double get distanceMetres => _distanceMetres;

  /// Adds a measured leg to the trip's distance.
  void addDistance(double metres) {
    if (!_isTracking || metres <= 0) return;
    _distanceMetres += metres;
  }

  void addRecord({
    required int speed,
    required int recommendedSpeed,
    required RiskBand riskBand,
    int? roadId,
    int? actualSpeedLimit,
    String? surface,
  }) {
    if (!_isTracking) return;

    if (_currentTrip == null) return;

    final now = DateTime.now();
    final isOverSpeed = speed > recommendedSpeed;
    // The previous state, read before this record is appended.
    final wasOverSpeed =
        _drivingRecords.isNotEmpty && _drivingRecords.last.isOverSpeed;

    final record = DrivingRecord(
      speed: speed,
      recommendedSpeed: recommendedSpeed,
      riskBand: riskBand,
      isOverSpeed: isOverSpeed,
      timestamp: now,
    );
    _drivingRecords.add(record);
    _speedSum += speed;
    _riskSum += riskBand.index;

    var alerts = List<SpeedAlert>.from(_currentTrip!.alerts);
    var overSpeedCount = _currentTrip!.overSpeedCount;

    // Over-speed is an episode with a start, an end and a peak — not a series
    // of independent point events. It used to be logged once per sample, so
    // the count described the recording rate rather than the driving.
    if (isOverSpeed && !wasOverSpeed) {
      overSpeedCount++;
      alerts.add(
        SpeedAlert(
          id: now.microsecondsSinceEpoch.toString(),
          time: now,
          speed: speed,
          peakSpeed: speed,
          recommendedSpeed: recommendedSpeed,
          type: AlertType.overSpeed,
        ),
      );
    } else if (isOverSpeed && alerts.isNotEmpty && alerts.last.isOpen) {
      // Still over: track the worst speed reached.
      if (speed > alerts.last.peakSpeed) {
        alerts[alerts.length - 1] = alerts.last.copyWith(peakSpeed: speed);
      }
    } else if (!isOverSpeed && alerts.isNotEmpty && alerts.last.isOpen) {
      // Back under the limit: close the episode.
      alerts[alerts.length - 1] = alerts.last.copyWith(endTime: now);
    }

    final maxSpeed = speed > _currentTrip!.maxSpeed ? speed : _currentTrip!.maxSpeed;
    final avgSpeed = (_speedSum / _drivingRecords.length).round();

    _currentTrip = _currentTrip!.copyWith(
      maxSpeed: maxSpeed,
      avgSpeed: avgSpeed,
      overSpeedCount: overSpeedCount,
      alerts: alerts,
      // Written per record so the trip carries where it was driven, not just
      // how fast. These five fields were declared, uploaded to S3 and never
      // assigned — every uploaded trip had five null or zero columns.
      roadSegmentId: roadId?.toString(),
      actualSpeedLimit: actualSpeedLimit,
      estimatedSurface: surface,
      avgRiskScore: _riskSum / _drivingRecords.length,
      distanceTraveledMeters: _distanceMetres.round(),
    );

    notifyListeners();
  }

  void stopRecording() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    debugPrint(
      '[TripService] Recording stopped. Total records: ${_drivingRecords.length}',
    );
  }

  // `updateTrip(currentSpeed, recommendedSpeed)` used to live here. It was
  // dead but public, and it counted an alert on every call with no edge
  // detection — wiring it up would have undone the Phase 3 fix that made
  // over-speed a per-episode event rather than a per-sample one. It also set
  // `avgSpeed = currentSpeed`, which is not an average. Use `addRecord`.

  Future<void> endTrip() async {
    if (_currentTrip != null) {
      stopRecording();
      final now = DateTime.now();

      // A trip that ends mid-overspeed would otherwise leave its last episode
      // open forever, with no end time and no duration.
      final alerts = List<SpeedAlert>.from(_currentTrip!.alerts);
      if (alerts.isNotEmpty && alerts.last.isOpen) {
        alerts[alerts.length - 1] = alerts.last.copyWith(endTime: now);
      }

      final completedTrip = _currentTrip!.copyWith(
        endTime: now,
        alerts: alerts,
        distanceTraveledMeters: _distanceMetres.round(),
      );
      _trips.add(completedTrip);
      _currentTrip = null;
      _isTracking = false;
      await _saveTrip(completedTrip);

      if (_cloudUploadService != null &&
          _settingsService?.autoUploadEnabled == true) {
        unawaited(_cloudUploadService!.uploadTrip(completedTrip));
      }

      notifyListeners();
    }
  }

  Future<void> deleteTrip(String id) async {
    _trips.removeWhere((t) => t.id == id);
    if (_repository != null) {
      await _repository!.deleteTrip(id);
    } else {
      await _storage?.saveTrips(_trips);
    }
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _trips.clear();
    if (_repository != null) {
      await _repository!.clear();
    } else {
      await _storage?.saveTrips(_trips);
    }
    notifyListeners();
  }

  /// Persists one trip and its records.
  ///
  /// The old path rewrote the entire history as one JSON string on every
  /// mutation, so both saving and loading were O(total history) and grew
  /// without bound. Writing a single trip is now a bounded operation.
  Future<void> _saveTrip(TripData trip) async {
    if (_repository != null) {
      await _repository!.saveTrip(trip, records: _drivingRecords);
      return;
    }
    await _storage?.saveTrips(_trips);
  }

  Map<String, dynamic> toJson() => {
    'trips': _trips.map((t) => t.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic> json) {
    _trips =
        (json['trips'] as List?)?.map((t) => TripData.fromJson(t)).toList() ??
        [];
    notifyListeners();
  }
}
