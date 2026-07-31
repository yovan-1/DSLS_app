import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/speed_model/road_conditions.dart';
import '../models/speed_model/speed_advisor.dart';
import '../models/speed_model/speed_recommendation.dart';

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

/// Cached evaluation of the current conditions.
///
/// This used to carry a `Color`, which put a UI decision inside a service. The
/// colour now lives in `lib/utils/speed_colors.dart` and is derived at render
/// time from [recommendation].
class RiskData {
  final SpeedRecommendation recommendation;

  const RiskData({required this.recommendation});

  int get recommendedSpeed => recommendation.recommendedSpeedKph;
  RiskBand get riskBand => recommendation.riskBand;
  String get riskLevel => recommendation.riskBand.label;
  List<String> get warnings =>
      recommendation.advisories.map((a) => a.message).toList();
}

class SpeedUpdate {
  final int rawGpsSpeed;
  final int smoothedSpeed;
  final int fusedSpeed;
  final RiskData? riskData;
  final DateTime timestamp;

  /// The fix this update was derived from, when there was one.
  ///
  /// Null on the synthetic update emitted by [GpsSpeedService.stopTracking].
  /// Consumers driving off this stream need the position to do zone matching,
  /// so carrying it here avoids a second stream and keeps the two in step.
  final Position? position;

  SpeedUpdate({
    required this.rawGpsSpeed,
    required this.smoothedSpeed,
    this.fusedSpeed = 0,
    this.riskData,
    required this.timestamp,
    this.position,
  });
}

enum GpsStatus { inactive, active, lost }

enum FusionStatus { gpsOnly, accelFusion, fullFusion }

/// Smoothing and animation constants for the speed readout.
///
/// This used to offer `sport`/`normal`/`smooth` presets selectable via
/// `setSensitivity()`, but nothing ever called that — the smoothing was always
/// `normal`. The presets are gone; the type stays because
/// [animationDurationMs] is still read by the speedometer widget.
class SpeedSensitivityConfig {
  final double alpha;
  final int animationDurationMs;
  final Duration throttleInterval;

  const SpeedSensitivityConfig({
    required this.alpha,
    required this.animationDurationMs,
    required this.throttleInterval,
  });

  static const normal = SpeedSensitivityConfig(
    alpha: 0.35,
    animationDurationMs: 30,
    throttleInterval: Duration(milliseconds: 50),
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
  static const Duration _accelHoldTimeout = Duration(seconds: 8);

  double _accelerometerDerivedSpeed = 0;
  DateTime? _lastAccelUpdate;
  bool _isDisposed = false;

  final _speedController = StreamController<SpeedUpdate>.broadcast();
  Stream<SpeedUpdate> get speedStream => _speedController.stream;

  RoadConditions? _lastConditions;
  RiskData? _cachedRiskData;
  DateTime? _lastRiskCalcTime;

  static const SpeedSensitivityConfig _sensitivity = SpeedSensitivityConfig.normal;

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

  SpeedSensitivityConfig get sensitivity => _sensitivity;

  void setRoadConditions(RoadConditions conditions) {
    _lastConditions = conditions;
    _cachedRiskData = null;
  }

  void updateFromAccelerometer(double speedMps) {
    if (_isDisposed) return;
    _accelerometerDerivedSpeed = speedMps * 3.6;
    _lastAccelUpdate = DateTime.now();
    _updateFusedSpeed();
    notifyListeners();
  }

  static RiskData _computeRisk(RoadConditions conditions) {
    return RiskData(recommendation: SpeedAdvisor.evaluate(conditions));
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
    if (_isDisposed) return;
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
    if (_lastConditions != null) {
      if (_lastRiskCalcTime == null ||
          now.difference(_lastRiskCalcTime!) > _sensitivity.throttleInterval) {
        _lastRiskCalcTime = now;
        _cachedRiskData = _computeRisk(_lastConditions!);
      }
    }

    _speedController.add(
      SpeedUpdate(
        rawGpsSpeed: rawSpeed,
        smoothedSpeed: _smoothedSpeed,
        fusedSpeed: _fusedSpeed,
        riskData: _cachedRiskData,
        timestamp: now,
        position: position,
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
    if (_isDisposed) return;
    if (_lastGpsUpdate != null && _gpsStatus == GpsStatus.active) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastGpsUpdate!);
      if (timeSinceLastUpdate.inSeconds > 60) {
        _gpsStatus = GpsStatus.lost;
        notifyListeners();
      }
    }
  }

  void _checkStaleSpeed() {
    if (_isDisposed || !_isTracking) return;

    _updateFusedSpeed();

    if (_lastGpsUpdate != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastGpsUpdate!);

      if (timeSinceLastUpdate > _staleTimeout) {
        final accelIsFresh = _lastAccelUpdate != null &&
            DateTime.now().difference(_lastAccelUpdate!) <= _accelHoldTimeout;

        if (!accelIsFresh) {
          if (_smoothedSpeed > 5) {
            _smoothedSpeed = (_smoothedSpeed * 0.7).round();
            if (_smoothedSpeed < 1) _smoothedSpeed = 0;
          } else {
            _smoothedSpeed = 0;
            _currentSpeed = 0;
          }
          _accelerometerDerivedSpeed = 0;
          _updateFusedSpeed();
        }
        // else: GPS stale but accel fresh — _updateFusedSpeed()'s existing
        // gpsTrust/accelTrust weighting already leans the blend toward the
        // accelerometer estimate.
      }
    }

    notifyListeners();
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
    _lastAccelUpdate = null;
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
    _isDisposed = true;
    _gpsCheckTimer?.cancel();
    _staleSpeedTimer?.cancel();
    _positionStream?.cancel();
    _speedController.close();
    super.dispose();
  }
}
