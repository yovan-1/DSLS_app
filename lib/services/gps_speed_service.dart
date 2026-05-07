import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart' hide DayPeriod;
import '../models/speed_calculator.dart';

class SpeedData {
  final int rawGpsSpeed;
  final int smoothedSpeed;
  final DateTime timestamp;

  SpeedData({
    required this.rawGpsSpeed,
    required this.smoothedSpeed,
    required this.timestamp,
  });
}

class RiskData {
  final int recommendedSpeed;
  final String riskLevel;
  final List<String> warnings;
  final Color speedColor;

  RiskData({
    required this.recommendedSpeed,
    required this.riskLevel,
    required this.warnings,
    required this.speedColor,
  });
}

class SpeedUpdate {
  final int rawGpsSpeed;
  final int smoothedSpeed;
  final RiskData? riskData;
  final DateTime timestamp;

  SpeedUpdate({
    required this.rawGpsSpeed,
    required this.smoothedSpeed,
    this.riskData,
    required this.timestamp,
  });
}

void _logDebug(String message) {
  debugPrint('[SpeedService] $message');
}

enum GpsStatus { inactive, active, lost }

class GpsSpeedService extends ChangeNotifier {
  StreamSubscription<Position>? _positionStream;
  Timer? _gpsCheckTimer;
  Timer? _staleSpeedTimer;

  int _currentSpeed = 0;
  int _smoothedSpeed = 0;
  int _zeroCounter = 0;
  bool _isTracking = false;
  bool _hasPermission = false;
  String? _errorMessage;
  Position? _lastPosition;
  DateTime? _lastUpdate;
  DateTime? _lastGpsUpdate;
  GpsStatus _gpsStatus = GpsStatus.inactive;

  final List<Position> _positionHistory = [];
  final List<int> _speedHistory = [];
  static const int _historySize = 5;
  static const int _speedHistorySize = 5;
  static const double _minMovementThreshold = 1.5;
  static const double _accuracyThreshold = 20.0;
  static const double _spikeThreshold = 0.50;
  static const Duration _staleTimeout = Duration(seconds: 3);
  static const int _zeroTimeoutCount = 2;

  final _speedController = StreamController<SpeedUpdate>.broadcast();
  Stream<SpeedUpdate> get speedStream => _speedController.stream;

  SpeedParameters? _lastParams;
  RiskData? _cachedRiskData;
  DateTime? _lastRiskCalcTime;
  static const _riskCalcInterval = Duration(milliseconds: 200);

  int get currentSpeed => _currentSpeed;
  int get smoothedSpeed => _smoothedSpeed;
  bool get isTracking => _isTracking;
  bool get hasPermission => _hasPermission;
  String? get errorMessage => _errorMessage;
  Position? get lastPosition => _lastPosition;
  GpsStatus get gpsStatus => _gpsStatus;

  void setCalculationParams(SpeedParameters params) {
    _lastParams = params;
    _cachedRiskData = null;
  }

  Future<RiskData> _calculateRiskAsync(int speed) async {
    if (_lastParams == null) {
      return RiskData(
        recommendedSpeed: 60,
        riskLevel: 'LOW',
        warnings: [],
        speedColor: Colors.grey,
      );
    }

    return _computeRisk(_lastParams!, speed);
  }

  static RiskData _computeRisk(SpeedParameters params, int currentSpeed) {
    final result = SpeedCalculator.calculate(params);
    final diff = currentSpeed - result.recommendedSpeed;

    Color speedColor;
    if (currentSpeed == 0) {
      speedColor = Colors.grey;
    } else if (diff <= 0) {
      speedColor = Colors.green;
    } else if (diff <= 10) {
      speedColor = Colors.yellow;
    } else {
      speedColor = Colors.red;
    }

    return RiskData(
      recommendedSpeed: result.recommendedSpeed,
      riskLevel:
          result.riskLevel >= 70
              ? 'HIGH'
              : (result.riskLevel >= 40 ? 'MEDIUM' : 'LOW'),
      warnings: result.warnings,
      speedColor: speedColor,
    );
  }

  RiskData? get cachedRiskData => _cachedRiskData;

  /// Checks and requests location permissions.
  ///
  /// Returns true if location services are enabled and permissions granted.
  /// Sets errorMessage if permission denied or services disabled.
  Future<bool> checkPermission() async {
    // Check if location services are enabled on device
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _errorMessage = "Location services are disabled";
      notifyListeners();
      return false;
    }

    // Check current permission status
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Request permission if not granted
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _errorMessage = "Location permissions are denied";
        notifyListeners();
        return false;
      }
    }

    // Check if permission is permanently denied
    if (permission == LocationPermission.deniedForever) {
      _errorMessage = "Location permissions are permanently denied";
      notifyListeners();
      return false;
    }

    _hasPermission = true;
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  /// Starts GPS tracking to monitor vehicle speed.
  ///
  /// Must call checkPermission() first to ensure permissions are granted.
  /// Uses high accuracy GPS with no distance filter for real-time updates.
  Future<void> startTracking() async {
    if (_isTracking) return; // Already tracking

    final hasPerms = await checkPermission();
    if (!hasPerms) return;

    _isTracking = true;
    _errorMessage = null;
    _gpsStatus = GpsStatus.active;
    _zeroCounter = 0;
    notifyListeners();

    // Start timer to check GPS status every 10 seconds
    _gpsCheckTimer = Timer.periodic(
      Duration(seconds: 10),
      (_) => _checkGpsStatus(),
    );

    // Start stale speed timer - if no update for 3 seconds, force speed to 0
    _staleSpeedTimer = Timer.periodic(
      Duration(seconds: 1),
      (_) => _checkStaleSpeed(),
    );

    // Configure GPS to use best for navigation accuracy with no distance filter
    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    // Start listening to position stream
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onPositionUpdate,
      onError: (error) {
        _errorMessage = error.toString();
        _isTracking = false;
        notifyListeners();
      },
    );
  }

  /// Handles incoming GPS position updates.
  ///
  /// Applies noise filtering, stationary detection, accuracy validation,
  /// and smoothed transitions for realistic speed readings.
  void _onPositionUpdate(Position position) {
    _lastGpsUpdate = DateTime.now();
    _gpsStatus = GpsStatus.active;

    _positionHistory.add(position);
    if (_positionHistory.length > _historySize) {
      _positionHistory.removeAt(0);
    }

    final accuracy = position.accuracy;
    final gpsSpeedMps = position.speed;
    int rawSpeed = 0;
    int filteredSpeed = 0;

    _logDebug(
      'GPS accuracy: ${accuracy.toStringAsFixed(1)}m, speed: ${gpsSpeedMps.toStringAsFixed(2)} m/s',
    );

    if (accuracy > _accuracyThreshold) {
      _logDebug(
        'Ignoring reading - poor accuracy ${accuracy.toStringAsFixed(1)}m > $_accuracyThreshold m',
      );
    } else if (gpsSpeedMps > 0 && !gpsSpeedMps.isNaN) {
      rawSpeed = (gpsSpeedMps * 3.6).round();

      if (gpsSpeedMps < _minMovementThreshold) {
        _logDebug(
          'Speed ${gpsSpeedMps.toStringAsFixed(2)} m/s < $_minMovementThreshold m/s - treating as stationary',
        );
        filteredSpeed = 0;
      } else {
        filteredSpeed = rawSpeed.clamp(0, 300);
      }
    } else if (_lastPosition != null && _lastUpdate != null) {
      final timeDiff =
          position.timestamp.difference(_lastUpdate!).inMilliseconds;
      if (timeDiff > 0) {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        final calcSpeedMps = distance / (timeDiff / 1000);
        rawSpeed = (calcSpeedMps * 3.6).round();

        if (calcSpeedMps < _minMovementThreshold) {
          filteredSpeed = 0;
        } else {
          filteredSpeed = rawSpeed.clamp(0, 300);
        }
      }
    }

    double totalMovement = 0;
    for (int i = 1; i < _positionHistory.length; i++) {
      totalMovement += Geolocator.distanceBetween(
        _positionHistory[i - 1].latitude,
        _positionHistory[i - 1].longitude,
        _positionHistory[i].latitude,
        _positionHistory[i].longitude,
      );
    }
    final isStationary = totalMovement < 10 && _positionHistory.length >= 3;
    if (isStationary) {
      _zeroCounter++;
      _logDebug(
        'Stationary detected - total movement: ${totalMovement.toStringAsFixed(1)}m, counter: $_zeroCounter',
      );
      if (_zeroCounter >= _zeroTimeoutCount) {
        filteredSpeed = 0;
      }
    } else {
      _zeroCounter = 0;
    }

    _currentSpeed = filteredSpeed;

    _speedHistory.add(filteredSpeed);
    if (_speedHistory.length > _speedHistorySize) {
      _speedHistory.removeAt(0);
    }

    int finalSpeed = filteredSpeed;

    if (_speedHistory.length >= 3) {
      int lastRecordedSpeed =
          _speedHistory.length >= 2
              ? _speedHistory[_speedHistory.length - 2]
              : filteredSpeed;

      if (lastRecordedSpeed > 0) {
        double changeRatio =
            (filteredSpeed - lastRecordedSpeed).abs() / lastRecordedSpeed;

        if (changeRatio > _spikeThreshold) {
          _logDebug(
            'SPIKE DETECTED: change ${(changeRatio * 100).toStringAsFixed(1)}% > ${(_spikeThreshold * 100).toStringAsFixed(0)}% - using previous: $lastRecordedSpeed',
          );
          finalSpeed = lastRecordedSpeed;
        }
      }
    }

    int movingAvg = 0;
    if (_speedHistory.isNotEmpty) {
      movingAvg =
          (_speedHistory.reduce((a, b) => a + b) / _speedHistory.length)
              .round();
    }

    if (filteredSpeed == 0 && _smoothedSpeed > 0) {
      _smoothedSpeed = (_smoothedSpeed * 0.5).round();
      if (_smoothedSpeed < 1) _smoothedSpeed = 0;
    } else if (_smoothedSpeed > 0 && finalSpeed == 0) {
      _smoothedSpeed = (_smoothedSpeed * 0.5).round();
      if (_smoothedSpeed < 1) _smoothedSpeed = 0;
    } else {
      double avgComponent = movingAvg * 0.45;
      double currentComponent = finalSpeed * 0.55;
      _smoothedSpeed = (avgComponent + currentComponent).round().clamp(0, 300);
    }

    _logDebug(
      'RAW: $rawSpeed | FILTERED: $filteredSpeed | AVG: $movingAvg | FINAL: $finalSpeed | SMOOTHED: $_smoothedSpeed',
    );

    debugPrint(
      '[GPS Speed] smoothedSpeed = $_smoothedSpeed, cachedRiskData = ${_cachedRiskData?.recommendedSpeed}',
    );

    _lastPosition = position;
    _lastUpdate = position.timestamp;

    RiskData? riskData;
    final now = DateTime.now();
    if (_lastParams != null &&
        (_lastRiskCalcTime == null ||
            now.difference(_lastRiskCalcTime!) > _riskCalcInterval)) {
      _lastRiskCalcTime = now;
      _calculateRiskAsync(_smoothedSpeed).then((data) {
        _cachedRiskData = data;
        _speedController.add(
          SpeedUpdate(
            rawGpsSpeed: rawSpeed,
            smoothedSpeed: _smoothedSpeed,
            riskData: data,
            timestamp: now,
          ),
        );
        _logDebug('UI UPDATE TRIGGERED with risk data');
        notifyListeners();
      });
      riskData = _cachedRiskData;
    } else {
      riskData = _cachedRiskData;
    }

    _speedController.add(
      SpeedUpdate(
        rawGpsSpeed: rawSpeed,
        smoothedSpeed: _smoothedSpeed,
        riskData: riskData,
        timestamp: now,
      ),
    );
    notifyListeners();
  }

  /// Checks if GPS signal has been lost.
  ///
  /// If no GPS update received for more than 60 seconds, marks GPS as lost.
  void _checkGpsStatus() {
    if (_lastGpsUpdate != null && _gpsStatus == GpsStatus.active) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastGpsUpdate!);
      if (timeSinceLastUpdate.inSeconds > 60) {
        _gpsStatus = GpsStatus.lost;
        notifyListeners();
      }
    }
  }

  /// Checks if speed data is stale and resets to zero if needed.
  void _checkStaleSpeed() {
    if (!_isTracking) return;
    
    if (_lastGpsUpdate != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastGpsUpdate!);
      
      if (timeSinceLastUpdate > _staleTimeout) {
        _smoothedSpeed = 0;
        _currentSpeed = 0;
        _zeroCounter = 0;
        notifyListeners();
      }
    }
  }

  /// Stops GPS tracking and resets all values.
  Future<void> stopTracking() async {
    _gpsCheckTimer?.cancel();
    _gpsCheckTimer = null;
    _staleSpeedTimer?.cancel();
    _staleSpeedTimer = null;
    await _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    _currentSpeed = 0;
    _smoothedSpeed = 0;
    _zeroCounter = 0;
    _lastPosition = null;
    _lastUpdate = null;
    _gpsStatus = GpsStatus.inactive;
    _cachedRiskData = null;
    _positionHistory.clear();
    _speedHistory.clear();
    _speedController.add(
      SpeedUpdate(rawGpsSpeed: 0, smoothedSpeed: 0, timestamp: DateTime.now()),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _gpsCheckTimer?.cancel();
    _staleSpeedTimer?.cancel();
    _positionStream?.cancel();
    _speedController.close();
    super.dispose();
  }
}
