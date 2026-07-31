import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/motion/dead_reckoning.dart';

/// One reading of vehicle motion, for consumers that want every sample rather
/// than the throttled [ChangeNotifier] view.
@immutable
class MotionSample {
  final DateTime timestamp;
  final double speedEstimateMps;
  final double forwardAccelMps2;
  final double headingRateRadPerSec;
  final bool orientationKnown;

  const MotionSample({
    required this.timestamp,
    required this.speedEstimateMps,
    required this.forwardAccelMps2,
    required this.headingRateRadPerSec,
    required this.orientationKnown,
  });
}

/// Platform adapter over the accelerometer and gyroscope.
///
/// All the physics lives in [DeadReckoningEstimator] so it can be tested
/// without a device; this class only handles subscriptions, rate limiting and
/// availability.
class MotionSensorService extends ChangeNotifier {
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<UserAccelerometerEvent>? _userAccelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  final DeadReckoningEstimator _estimator = DeadReckoningEstimator();
  final _sampleController = StreamController<MotionSample>.broadcast();

  double _headingRate = 0;
  DateTime? _lastUserAccelAt;
  DateTime? _lastNotifyAt;

  bool _isAvailable = false;
  bool _isInitialized = false;
  String? _errorMessage;

  static const int _sampleRateHz = 50;

  /// Listeners are UI. Sensors arrive at 50 Hz; nothing on screen changes
  /// usefully faster than this, and the previous code notified on every single
  /// event.
  static const Duration _notifyInterval = Duration(milliseconds: 250);

  bool get isAvailable => _isAvailable;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;

  double get speedEstimateMps => _estimator.speedEstimateMps;
  double get forwardAccelMps2 => _estimator.lastForwardAccelMps2;
  double get headingRateRadPerSec => _headingRate;

  /// False until the device→vehicle orientation has been learned from GPS. The
  /// speed estimate is only dead-reckoned once this is true; before that it is
  /// simply the last GPS speed.
  bool get orientationKnown => _estimator.orientationKnown;

  /// Seconds of integration since the last GPS correction — how stale the
  /// dead-reckoned estimate is.
  double get secondsSinceGpsFix => _estimator.secondsSinceGpsFix;

  Stream<MotionSample> get samples => _sampleController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _probeSensors();

      if (!_isAvailable) {
        _errorMessage = 'Motion sensors not available on this device';
        notifyListeners();
        return;
      }

      _startListening();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to initialize motion sensors: $e';
      if (kDebugMode) {
        debugPrint('[MotionSensor] Init error: $e');
      }
      notifyListeners();
    }
  }

  /// Corrects the integrator against a GPS fix, bounding drift by the fix
  /// interval, and lets the estimator refine the forward axis.
  void zeroAgainstGps(double gpsSpeedMps) {
    _estimator.zeroAgainstGps(gpsSpeedMps);
  }

  /// Releases the sensor subscriptions without disposing the service, so a
  /// later trip can call [initialize] again. Previously only [dispose] cancelled
  /// them, which meant the accelerometer kept streaming after a trip ended.
  void stop() {
    _cancelSubscriptions();
    _isInitialized = false;
    _headingRate = 0;
    _lastUserAccelAt = null;
    // The phone may be in a completely different pose next trip, so the learned
    // orientation must not carry over.
    _estimator.reset();
    notifyListeners();
  }

  Future<void> _probeSensors() async {
    try {
      final completer = Completer<bool>();
      StreamSubscription<AccelerometerEvent>? probe;
      probe = accelerometerEventStream().listen(
        (_) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      _isAvailable = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      await probe.cancel();
    } catch (_) {
      _isAvailable = false;
    }
  }

  void _startListening() {
    final period = Duration(milliseconds: 1000 ~/ _sampleRateHz);

    // Raw accelerometer, gravity included — used only to track which way down
    // is, which is what makes the forward axis recoverable in any phone pose.
    _accelSubscription =
        accelerometerEventStream(samplingPeriod: period).listen(
      (event) => _estimator.addRawAccel(Vector3(event.x, event.y, event.z)),
      onError: _onSensorError,
    );

    // Platform-provided and genuinely gravity-compensated, unlike the
    // hand-rolled subtraction this replaces.
    _userAccelSubscription =
        userAccelerometerEventStream(samplingPeriod: period).listen(
      _onUserAccelerometerEvent,
      onError: _onSensorError,
    );

    _gyroSubscription = gyroscopeEventStream(samplingPeriod: period).listen(
      (event) => _headingRate = event.z,
      onError: _onSensorError,
    );
  }

  void _onUserAccelerometerEvent(UserAccelerometerEvent event) {
    final now = DateTime.now();
    final last = _lastUserAccelAt;
    _lastUserAccelAt = now;
    if (last == null) return;

    final dt = now.difference(last).inMicroseconds / 1e6;
    _estimator.addUserAccel(Vector3(event.x, event.y, event.z), dt);

    final sample = MotionSample(
      timestamp: now,
      speedEstimateMps: _estimator.speedEstimateMps,
      forwardAccelMps2: _estimator.lastForwardAccelMps2,
      headingRateRadPerSec: _headingRate,
      orientationKnown: _estimator.orientationKnown,
    );
    if (_sampleController.hasListener) {
      _sampleController.add(sample);
    }

    _notifyThrottled(now);
  }

  void _notifyThrottled(DateTime now) {
    final last = _lastNotifyAt;
    if (last != null && now.difference(last) < _notifyInterval) return;
    _lastNotifyAt = now;
    notifyListeners();
  }

  void _onSensorError(Object error) {
    _errorMessage = 'Sensor error: $error';
    if (kDebugMode) {
      debugPrint('[MotionSensor] $error');
    }
  }

  void _cancelSubscriptions() {
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _userAccelSubscription?.cancel();
    _userAccelSubscription = null;
    _gyroSubscription?.cancel();
    _gyroSubscription = null;
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _sampleController.close();
    super.dispose();
  }
}
