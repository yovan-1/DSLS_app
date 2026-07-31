import 'dart:async';
import 'package:flutter/material.dart' hide DayPeriod;
import '../models/trip_data.dart';
import '../models/speed_model/road_conditions.dart';
import '../models/speed_model/speed_advisor.dart';
import '../models/speed_model/speed_recommendation.dart';
import 'offline_storage_service.dart';
import 'cloud_upload_service.dart';
import 'settings_service.dart';

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

  Future<void> loadTrips() async {
    if (_storage != null) {
      _trips = await _storage!.getTrips();
      notifyListeners();
    }
  }

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

  int get totalDistance {
    int total = 0;
    for (final trip in _trips) {
      final dur = trip.duration;
      if (dur != null) {
        total += (dur.inMinutes * trip.avgSpeed / 60).round();
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

  void addRecord({
    required int speed,
    required int recommendedSpeed,
    required RiskBand riskBand,
  }) {
    if (!_isTracking) return;

    if (_currentTrip == null) return;

    final now = DateTime.now();
    final isOverSpeed = speed > recommendedSpeed;
    final record = DrivingRecord(
      speed: speed,
      recommendedSpeed: recommendedSpeed,
      riskBand: riskBand,
      isOverSpeed: isOverSpeed,
      timestamp: now,
    );
    _drivingRecords.add(record);

    final alerts = List<SpeedAlert>.from(_currentTrip!.alerts);
    var overSpeedCount = _currentTrip!.overSpeedCount;

    // Count over-speed *episodes*, not samples. This used to fire on every
    // record, so a single 10-second overspeed was logged as one alert per
    // sampling tick — making the count a function of the recording rate rather
    // than of how the trip was actually driven. Only the rising edge counts;
    // `_drivingRecords.last` is the record just added, so the one before it is
    // the previous state.
    final wasOverSpeed = _drivingRecords.length >= 2 &&
        _drivingRecords[_drivingRecords.length - 2].isOverSpeed;

    if (isOverSpeed && !wasOverSpeed) {
      overSpeedCount++;
      alerts.add(
        SpeedAlert(
          id: now.microsecondsSinceEpoch.toString(),
          time: now,
          speed: speed,
          recommendedSpeed: recommendedSpeed,
          type: AlertType.overSpeed,
        ),
      );
    }

    final maxSpeed = speed > _currentTrip!.maxSpeed ? speed : _currentTrip!.maxSpeed;
    final avgSpeed = (_drivingRecords
                .map((record) => record.speed)
                .fold<int>(0, (total, value) => total + value) /
            _drivingRecords.length)
        .round();

    _currentTrip = _currentTrip!.copyWith(
      maxSpeed: maxSpeed,
      avgSpeed: avgSpeed,
      overSpeedCount: overSpeedCount,
      alerts: alerts,
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
      final completedTrip = _currentTrip!.copyWith(endTime: DateTime.now());
      _trips.add(completedTrip);
      _currentTrip = null;
      _isTracking = false;
      await _saveTrips();

      if (_cloudUploadService != null &&
          _settingsService?.autoUploadEnabled == true) {
        unawaited(_cloudUploadService!.uploadTrip(completedTrip));
      }

      notifyListeners();
    }
  }

  Future<void> deleteTrip(String id) async {
    _trips.removeWhere((t) => t.id == id);
    await _saveTrips();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _trips.clear();
    await _saveTrips();
    notifyListeners();
  }

  Future<void> _saveTrips() async {
    if (_storage != null) {
      await _storage!.saveTrips(_trips);
    }
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
