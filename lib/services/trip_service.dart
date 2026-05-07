import 'dart:async';
import 'package:flutter/material.dart' hide DayPeriod;
import '../models/speed_calculator.dart';
import '../models/trip_data.dart';
import 'offline_storage_service.dart';

class DrivingRecord {
  final int speed;
  final int recommendedSpeed;
  final String riskLevel;
  final bool isOverSpeed;
  final DateTime timestamp;

  DrivingRecord({
    required this.speed,
    required this.recommendedSpeed,
    required this.riskLevel,
    required this.isOverSpeed,
    required this.timestamp,
  });
}

class TripService extends ChangeNotifier {
  List<TripData> _trips = [];
  TripData? _currentTrip;
  bool _isTracking = false;
  OfflineStorageService? _storage;

  final List<DrivingRecord> _drivingRecords = [];
  Timer? _recordingTimer;

  List<TripData> get trips => _trips;
  TripData? get currentTrip => _currentTrip;
  bool get isTracking => _isTracking;

  void setStorage(OfflineStorageService storage) {
    _storage = storage;
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
            .where((r) => r.isOverSpeed == false && r.riskLevel != 'HIGH')
            .length;
    return ((safeCount / _drivingRecords.length) * 100).round();
  }

  int get moderateDrivingPercent {
    if (_drivingRecords.isEmpty) return 0;
    int modCount =
        _drivingRecords.where((r) {
          if (r.isOverSpeed && r.riskLevel != 'HIGH') return true;
          if (!r.isOverSpeed && r.riskLevel == 'MEDIUM') return true;
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
                  r.riskLevel == 'HIGH' ||
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

  void startTrip(SpeedParameters params) {
    _drivingRecords.clear();
    final result = SpeedCalculator.calculate(params);
    _currentTrip = TripData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now(),
      location: params.location,
      baseSpeedLimit: params.baseSpeedLimit,
      recommendedSpeed: result.recommendedSpeed,
    );
    _isTracking = true;
    notifyListeners();
  }

  void addRecord({
    required int speed,
    required int recommendedSpeed,
    required String riskLevel,
  }) {
    debugPrint(
      '[TripService.addRecord] _isTracking=$_isTracking, speed=$speed, rec=$recommendedSpeed, risk=$riskLevel',
    );
    if (!_isTracking) {
      debugPrint('[TripService.addRecord] REJECTED - not tracking');
      return;
    }

    if (_currentTrip == null) return;

    final now = DateTime.now();
    final isOverSpeed = speed > recommendedSpeed;
    final record = DrivingRecord(
      speed: speed,
      recommendedSpeed: recommendedSpeed,
      riskLevel: riskLevel,
      isOverSpeed: isOverSpeed,
      timestamp: now,
    );
    _drivingRecords.add(record);

    final alerts = List<SpeedAlert>.from(_currentTrip!.alerts);
    var overSpeedCount = _currentTrip!.overSpeedCount;

    if (isOverSpeed) {
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

    debugPrint(
      '[TripService] RECORD ADDED: ${_drivingRecords.length} records stored',
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

  void updateTrip(int currentSpeed, int recommendedSpeed) {
    if (_currentTrip == null) return;

    final alerts = List<SpeedAlert>.from(_currentTrip!.alerts);
    int overSpeedCount = _currentTrip!.overSpeedCount;

    if (currentSpeed > recommendedSpeed) {
      overSpeedCount++;
      alerts.add(
        SpeedAlert(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          time: DateTime.now(),
          speed: currentSpeed,
          recommendedSpeed: recommendedSpeed,
          type: AlertType.overSpeed,
        ),
      );
    }

    final speeds = List<int>.from(
      _currentTrip!.maxSpeed > 0
          ? [_currentTrip!.maxSpeed, currentSpeed]
          : [currentSpeed],
    );
    final maxSpeed = speeds.reduce((a, b) => a > b ? a : b);
    final avgSpeed = currentSpeed;

    _currentTrip = _currentTrip!.copyWith(
      maxSpeed: maxSpeed,
      avgSpeed: avgSpeed,
      overSpeedCount: overSpeedCount,
      alerts: alerts,
    );
    notifyListeners();
  }

  void endTrip() {
    if (_currentTrip != null) {
      stopRecording();
      final completedTrip = _currentTrip!.copyWith(endTime: DateTime.now());
      _trips.add(completedTrip);
      _currentTrip = null;
      _isTracking = false;
      _saveTrips();
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
