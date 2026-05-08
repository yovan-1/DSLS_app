import 'dart:async';
import 'package:flutter/foundation.dart';
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
  final int fusedSpeed;
  final RiskData? riskData;
  final DateTime timestamp;

  SpeedUpdate({
    required this.rawGpsSpeed,
    required this.smoothedSpeed,
    this.fusedSpeed = 0,
    this.riskData,
    required this.timestamp,
  });
}

enum GpsStatus { inactive, active, lost }

enum FusionStatus { gpsOnly, accelFusion, fullFusion }

class SpeedSensitivityConfig {
  final double alpha;
  final int animationDurationMs;
  final Duration throttleInterval;

  const SpeedSensitivityConfig({
    required this.alpha,
    required this.animationDurationMs,
    required this.throttleInterval,
  });

  static const sport = SpeedSensitivityConfig(
    alpha: 0.5,
    animationDurationMs: 16,
    throttleInterval: Duration(milliseconds: 33),
  );

  static const normal = SpeedSensitivityConfig(
    alpha: 0.35,
    animationDurationMs: 30,
    throttleInterval: Duration(milliseconds: 50),
  );

  static const smooth = SpeedSensitivityConfig(
    alpha: 0.2,
    animationDurationMs: 60,
    throttleInterval: Duration(milliseconds: 100),
  );
}

class GpsSpeedService extends ChangeNotifier {
  StreamSubscription<Position>? _positionStream;
  Timer? _gpsCheckTimer;
  Timer? _staleSpeedTimer;

  int _currentSpeed = 0;
  int _smoothedSpeed = 0;
  int _fusedSpeed = 0;
  bool _isTracking = false;
  bool _hasPermission = false;
  String? _errorMessage;
  Position? _lastPosition;
  DateTime? _lastUpdate;
  DateTime? _lastGpsUpdate;
  GpsStatus _gpsStatus = GpsStatus.inactive;
  FusionStatus _fusionStatus = FusionStatus.gpsOnly;

  final List<Position> _positionHistory = [];
  final List<int> _speedHistory = [];
  static const int _historySize = 3;
  static const int _speedHistorySize = 3;
  static const double _minMovementThreshold = 0.5;
  static const double _accuracyThreshold = 25.0;
  static const double _spikeThreshold = 0.40;
  static const Duration _staleTimeout = Duration(seconds: 2);

  double _accelerometerDerivedSpeed = 0;

  final _speedController = StreamController<SpeedUpdate>.broadcast();
  Stream<SpeedUpdate> get speedStream => _speedController.stream;

  SpeedParameters? _lastParams;
  RiskData? _cachedRiskData;
  DateTime? _lastRiskCalcTime;

  SpeedSensitivityConfig _sensitivity = SpeedSensitivityConfig.normal;

  int get currentSpeed => _currentSpeed;
  int get smoothedSpeed => _smoothedSpeed;
  int get fusedSpeed => _fusedSpeed;
  bool get isTracking => _isTracking;
  bool get hasPermission => _hasPermission;
  String? get errorMessage => _errorMessage;
  Position? get lastPosition => _lastPosition;
  GpsStatus get gpsStatus => _gpsStatus;
  FusionStatus get fusionStatus => _fusionStatus;
  int get animationDurationMs => _sensitivity.animationDurationMs;

  void setSensitivity(SpeedSensitivityConfig sensitivity) {
    _sensitivity = sensitivity;
    notifyListeners();
  }

  SpeedSensitivityConfig get sensitivity => _sensitivity;

  void setCalculationParams(SpeedParameters params) {
    _lastParams = params;
    _cachedRiskData = null;
  }

  void updateFromAccelerometer(double speedMps) {
    _accelerometerDerivedSpeed = speedMps * 3.6;
    _fusionStatus = FusionStatus.accelFusion;
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

  Future<bool> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _errorMessage = "Location services are disabled";
      notifyListeners();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _errorMessage = "Location permissions are denied";
        notifyListeners();
        return false;
      }
    }

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

  Future<void> startTracking() async {
    if (_isTracking) return;

    final hasPerms = await checkPermission();
    if (!hasPerms) return;

    _isTracking = true;
    _errorMessage = null;
    _gpsStatus = GpsStatus.active;
    _smoothedSpeed = 0;
    _fusedSpeed = 0;
    _cachedRiskData = null;
    notifyListeners();

    _gpsCheckTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkGpsStatus(),
    );

    _staleSpeedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkStaleSpeed(),
    );

    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

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

    if (accuracy > _accuracyThreshold) {
      if (kDebugMode) {
        debugPrint('[GPS] Low accuracy: ${accuracy.toStringAsFixed(1)}m');
      }
    } else if (gpsSpeedMps > 0 && !gpsSpeedMps.isNaN) {
      rawSpeed = (gpsSpeedMps * 3.6).round();

      if (gpsSpeedMps < _minMovementThreshold) {
        if (kDebugMode) {
          debugPrint('[GPS] Stationary: ${gpsSpeedMps.toStringAsFixed(2)} m/s');
        }
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

    _currentSpeed = filteredSpeed;

    _speedHistory.add(filteredSpeed);
    if (_speedHistory.length > _speedHistorySize) {
      _speedHistory.removeAt(0);
    }

    int finalSpeed = filteredSpeed;

    if (_speedHistory.length >= 2) {
      int lastRecordedSpeed = _speedHistory[_speedHistory.length - 2];
      if (lastRecordedSpeed > 0) {
        double changeRatio =
            (filteredSpeed - lastRecordedSpeed).abs() / lastRecordedSpeed;
        if (changeRatio > _spikeThreshold) {
          if (kDebugMode) {
            debugPrint('[GPS] Spike filtered: ${(changeRatio * 100).toStringAsFixed(1)}%');
          }
          finalSpeed = lastRecordedSpeed;
        }
      }
    }

    if (filteredSpeed == 0 && _smoothedSpeed > 0) {
      _smoothedSpeed = (_smoothedSpeed * 0.3).round();
      if (_smoothedSpeed < 1) _smoothedSpeed = 0;
    } else if (_smoothedSpeed > 0 && finalSpeed == 0) {
      _smoothedSpeed = (_smoothedSpeed * 0.3).round();
      if (_smoothedSpeed < 1) _smoothedSpeed = 0;
    } else {
      final alpha = _sensitivity.alpha;
      _smoothedSpeed = (_smoothedSpeed * (1 - alpha) + finalSpeed * alpha).round().clamp(0, 300);
    }

    _updateFusedSpeed();

    _lastPosition = position;
    _lastUpdate = position.timestamp;

    final now = DateTime.now();
    if (_lastParams != null) {
      if (_lastRiskCalcTime == null ||
          now.difference(_lastRiskCalcTime!) > _sensitivity.throttleInterval) {
        _lastRiskCalcTime = now;
        _cachedRiskData = _computeRisk(_lastParams!, _fusedSpeed);
      }
    }

    _speedController.add(
      SpeedUpdate(
        rawGpsSpeed: rawSpeed,
        smoothedSpeed: _smoothedSpeed,
        fusedSpeed: _fusedSpeed,
        riskData: _cachedRiskData,
        timestamp: now,
      ),
    );
    notifyListeners();
  }

  void _updateFusedSpeed() {
    double gpsTrust = 1.0;

    if (_lastPosition != null) {
      final accuracy = _lastPosition!.accuracy;
      if (accuracy > _accuracyThreshold) {
        gpsTrust = 0.5;
      }

      if (_lastGpsUpdate != null) {
        final timeSince = DateTime.now().difference(_lastGpsUpdate!);
        if (timeSince.inSeconds > 2) {
          gpsTrust *= 0.7;
        }
        if (timeSince.inSeconds > 5) {
          gpsTrust *= 0.5;
        }
      }
    }

    final accelTrust = 1.0 - gpsTrust;
    _fusedSpeed = ((_smoothedSpeed * gpsTrust) + (_accelerometerDerivedSpeed * accelTrust)).round().clamp(0, 300);

    if (gpsTrust > 0.8) {
      _fusionStatus = FusionStatus.gpsOnly;
    } else if (gpsTrust > 0.3) {
      _fusionStatus = FusionStatus.accelFusion;
    } else {
      _fusionStatus = FusionStatus.fullFusion;
    }
  }

  void _checkGpsStatus() {
    if (_lastGpsUpdate != null && _gpsStatus == GpsStatus.active) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastGpsUpdate!);
      if (timeSinceLastUpdate.inSeconds > 60) {
        _gpsStatus = GpsStatus.lost;
        notifyListeners();
      }
    }
  }

  void _checkStaleSpeed() {
    if (!_isTracking) return;

    if (_lastGpsUpdate != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastGpsUpdate!);

      if (timeSinceLastUpdate > _staleTimeout) {
        if (_smoothedSpeed > 5) {
          _smoothedSpeed = (_smoothedSpeed * 0.7).round();
          if (_smoothedSpeed < 1) _smoothedSpeed = 0;
          notifyListeners();
        } else {
          _smoothedSpeed = 0;
          _currentSpeed = 0;
          notifyListeners();
        }
      }
    }
  }

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
    _fusedSpeed = 0;
    _lastPosition = null;
    _lastUpdate = null;
    _gpsStatus = GpsStatus.inactive;
    _cachedRiskData = null;
    _accelerometerDerivedSpeed = 0;
    _fusionStatus = FusionStatus.gpsOnly;
    _positionHistory.clear();
    _speedHistory.clear();
    _speedController.add(
      SpeedUpdate(rawGpsSpeed: 0, smoothedSpeed: 0, fusedSpeed: 0, timestamp: DateTime.now()),
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
