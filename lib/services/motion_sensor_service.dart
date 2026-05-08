import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class MotionSensorService extends ChangeNotifier {
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  double _accelX = 0;
  double _accelY = 0;
  double _accelZ = 0;

  double _gyroX = 0;
  double _gyroY = 0;
  double _gyroZ = 0;

  double _linearAccelX = 0;
  double _linearAccelY = 0;
  double _linearAccelZ = 0;

  double _speedEstimateMps = 0;

  DateTime? _lastUpdate;
  bool _isAvailable = false;
  bool _isInitialized = false;
  String? _errorMessage;

  static const double _gravityMagnitude = 9.81;
  static const double _lowPassAlpha = 0.1;
  static const int _sampleRateHz = 50;

  bool get isAvailable => _isAvailable;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  double get speedEstimateMps => _speedEstimateMps;

  double get accelX => _accelX;
  double get accelY => _accelY;
  double get accelZ => _accelZ;

  double get gyroX => _gyroX;
  double get gyroY => _gyroY;
  double get gyroZ => _gyroZ;

  double get linearAccelX => _linearAccelX;
  double get linearAccelY => _linearAccelY;
  double get linearAccelZ => _linearAccelZ;

  double get headingRate => _gyroZ;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _testSensors();

      if (!_isAvailable) {
        _errorMessage = 'Motion sensors not available on this device';
        if (kDebugMode) {
          debugPrint('[MotionSensor] Sensors not available');
        }
        notifyListeners();
        return;
      }

      _startListening();
      _isInitialized = true;

      if (kDebugMode) {
        debugPrint('[MotionSensor] Initialized successfully');
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to initialize motion sensors: $e';
      if (kDebugMode) {
        debugPrint('[MotionSensor] Init error: $e');
      }
      notifyListeners();
    }
  }

  Future<void> _testSensors() async {
    try {
      final accelStream = accelerometerEventStream();
      final completer = Completer<bool>();

      StreamSubscription<AccelerometerEvent>? testSub;
      testSub = accelStream.listen(
        (event) {
          if (!completer.isCompleted) {
            completer.complete(true);
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
      );

      final result = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );

      await testSub.cancel();
      _isAvailable = result;
    } catch (e) {
      _isAvailable = false;
    }
  }

  void _startListening() {
    _accelSubscription = accelerometerEventStream(
      samplingPeriod: Duration(milliseconds: 1000 ~/ _sampleRateHz),
    ).listen(
      _onAccelerometerEvent,
      onError: (error) {
        _errorMessage = 'Accelerometer error: $error';
        if (kDebugMode) {
          debugPrint('[MotionSensor] Accelerometer error: $error');
        }
      },
    );

    _gyroSubscription = gyroscopeEventStream(
      samplingPeriod: Duration(milliseconds: 1000 ~/ _sampleRateHz),
    ).listen(
      _onGyroscopeEvent,
      onError: (error) {
        if (kDebugMode) {
          debugPrint('[MotionSensor] Gyroscope error: $error');
        }
      },
    );
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    final now = DateTime.now();

    _accelX = _lowPassFilter(_accelX, event.x, _lowPassAlpha);
    _accelY = _lowPassFilter(_accelY, event.y, _lowPassAlpha);
    _accelZ = _lowPassFilter(_accelZ, event.z, _lowPassAlpha);

    _computeLinearAcceleration(now);

    _updateSpeedEstimate(now);

    notifyListeners();
  }

  void _onGyroscopeEvent(GyroscopeEvent event) {
    _gyroX = _lowPassFilter(_gyroX, event.x, _lowPassAlpha);
    _gyroY = _lowPassFilter(_gyroY, event.y, _lowPassAlpha);
    _gyroZ = _lowPassFilter(_gyroZ, event.z, _lowPassAlpha);
  }

  void _computeLinearAcceleration(DateTime now) {
    final totalAccel = math.sqrt(_accelX * _accelX + _accelY * _accelY + _accelZ * _accelZ);

    double gravityX = 0, gravityY = 0, gravityZ = 0;
    if (totalAccel > 0) {
      gravityX = (_accelX / totalAccel) * _gravityMagnitude;
      gravityY = (_accelY / totalAccel) * _gravityMagnitude;
      gravityZ = (_accelZ / totalAccel) * _gravityMagnitude;
    }

    _linearAccelX = _accelX - gravityX;
    _linearAccelY = _accelY - gravityY;
    _linearAccelZ = _accelZ - gravityZ;
  }

  void _updateSpeedEstimate(DateTime now) {
    if (_lastUpdate == null) {
      _lastUpdate = now;
      return;
    }

    final dt = now.difference(_lastUpdate!).inMicroseconds / 1000000.0;
    if (dt <= 0 || dt > 1.0) {
      _lastUpdate = now;
      return;
    }

    final accelMagnitude = math.sqrt(
      _linearAccelX * _linearAccelX +
      _linearAccelY * _linearAccelY +
      _linearAccelZ * _linearAccelZ,
    );

    final bool isStationary = _detectStationary(accelMagnitude);

    if (isStationary) {
      _speedEstimateMps = 0;
      _lastUpdate = now;
      return;
    }

    final forwardAccel = -_linearAccelY;

    _speedEstimateMps += forwardAccel * dt;

    _speedEstimateMps = _speedEstimateMps.clamp(0.0, 50.0);

    _lastUpdate = now;
  }

  bool _detectStationary(double accelMagnitude) {
    const stationaryThreshold = 0.3;

    if (accelMagnitude < stationaryThreshold) {
      return true;
    }

    if (_speedEstimateMps < 0.5 && accelMagnitude < 0.5) {
      return true;
    }

    return false;
  }

  double _lowPassFilter(double previous, double current, double alpha) {
    return previous + alpha * (current - previous);
  }

  bool isTurning(double threshold) {
    return _gyroZ.abs() > threshold;
  }

  double getMotionIntensity() {
    final accelMagnitude = math.sqrt(_accelX * _accelX + _accelY * _accelY + _accelZ * _accelZ);
    final gyroMagnitude = math.sqrt(_gyroX * _gyroX + _gyroY * _gyroY + _gyroZ * _gyroZ);

    return (accelMagnitude / _gravityMagnitude + gyroMagnitude) / 2.0;
  }

  @override
  void dispose() {
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    super.dispose();
  }
}
