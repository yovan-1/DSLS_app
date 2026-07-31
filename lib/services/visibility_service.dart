import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide DayPeriod;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../models/speed_calculator.dart';

/// Measures ambient light through the rear camera.
///
/// Two things changed here from the original. First, camera- and
/// weather-derived visibility are kept as separate fields. They used to share
/// one, so every camera sample — every 5 to 30 seconds — silently erased the
/// weather degradation, which was only recomputed on a weather fetch every 30
/// minutes. In practice the weather penalty was almost never in effect.
///
/// Second, "the camera cannot see" is now represented as null rather than as
/// [VisibilityLevel.veryPoor]. A phone in a pocket, a backgrounded app and a
/// genuinely dark road are three different situations, and only the last one
/// should slow the driver down. The speed model already treats a null camera
/// reading as "unknown" and falls back to solar elevation plus weather, which
/// works in a pocket.
class VisibilityService extends ChangeNotifier {
  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _permissionDenied = false;
  bool _suspended = false;
  double _ambientBrightness = 128;

  /// Measured ambient light, or null when the camera cannot see: not yet
  /// started, released while backgrounded, or reading pocket-dark while moving.
  VisibilityLevel? _cameraVisibility;

  /// The visibility ceiling implied by the weather alone. Null until a weather
  /// reading arrives.
  VisibilityLevel? _weatherVisibility;

  Timer? _brightnessTimer;
  List<CameraDescription>? _cameras;

  static const int _minIntervalSeconds = 5;
  static const int _maxIntervalSeconds = 30;
  static const double _stabilityThreshold = 0.10;

  /// Below this the sensor is seeing essentially nothing. Combined with the
  /// vehicle moving, that is a covered lens rather than a dark road — no real
  /// windscreen view is this black even at night, because of headlights.
  static const double pocketBrightnessThreshold = 8.0;

  /// Consecutive pocket-dark samples before believing it. One frame can be a
  /// hand passing over the lens.
  static const int pocketSampleCount = 2;

  /// Below this the vehicle is not really moving, so a dark lens says nothing.
  static const int pocketMinSpeedKph = 20;

  final List<double> _brightnessHistory = [];
  static const int _historySize = 5;
  int _currentIntervalSeconds = _minIntervalSeconds;
  bool _isStable = true;
  bool _isDisposed = false;
  int _consecutiveDarkSamples = 0;
  int _vehicleSpeedKph = 0;

  double get ambientBrightness => _ambientBrightness;
  bool get isInitialized => _isInitialized;
  bool get permissionDenied => _permissionDenied;
  bool get isSuspended => _suspended;
  bool get isAvailable => _isInitialized && !_permissionDenied;
  bool get isStable => _isStable;

  /// Measured ambient light. Null means the camera cannot see — feed this
  /// straight to the speed model, which handles the unknown case.
  VisibilityLevel? get cameraVisibility => _cameraVisibility;

  VisibilityLevel? get weatherVisibility => _weatherVisibility;

  /// The worse of the camera and weather assessments, for display. Null when
  /// neither is known.
  VisibilityLevel? get effectiveVisibility {
    final camera = _cameraVisibility;
    final weather = _weatherVisibility;
    if (camera == null) return weather;
    if (weather == null) return camera;
    // VisibilityLevel is ordered best to worst, so the higher index is worse.
    return camera.index >= weather.index ? camera : weather;
  }

  Future<void> initialize() async {
    if (_isDisposed) return;
    if (_isInitialized) return;

    _suspended = false;
    // Re-checked on every attempt rather than latched: the user may have
    // granted the camera in Settings since the last try.
    _permissionDenied = false;

    try {
      // Check, do not request. Firing a bare system prompt from here is what
      // the app used to do, with no explanation of what the camera is for —
      // PermissionFlow now asks properly, behind a rationale, before the drive
      // starts. If the answer was no, this service simply stays quiet and the
      // model falls back to solar elevation and weather.
      final status = await Permission.camera.status;
      if (!status.isGranted) {
        _permissionDenied = true;
        debugPrint("[VisibilityService] Camera permission not granted");
        notifyListeners();
        return;
      }

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        notifyListeners();
        return;
      }

      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      _isInitialized = true;
      notifyListeners();
      _startBrightnessMonitoring();
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  /// Tells the service how fast the vehicle is going, so it can tell a pocketed
  /// phone from a dark road.
  void updateVehicleSpeed(int speedKph) {
    _vehicleSpeedKph = speedKph;
  }

  /// Releases the camera when the app is backgrounded. Android revokes it
  /// anyway; the point is to stop reporting the last thing the lens saw as if
  /// it were current.
  Future<void> suspend() async {
    if (_suspended) return;
    _suspended = true;
    await _releaseCamera();
    _setCameraVisibility(null);
  }

  /// Re-acquires the camera after the app returns to the foreground.
  Future<void> resume() async {
    if (!_suspended) return;
    _suspended = false;
    await initialize();
  }

  void _startBrightnessMonitoring() {
    _currentIntervalSeconds = _minIntervalSeconds;
    _isStable = true;
    _brightnessHistory.clear();
    _consecutiveDarkSamples = 0;
    _scheduleNextCheck();
  }

  void _scheduleNextCheck() {
    if (_isDisposed || _suspended) return;
    _brightnessTimer?.cancel();
    _brightnessTimer = Timer(Duration(seconds: _currentIntervalSeconds), () {
      if (_isDisposed || _suspended) return;
      _captureAndProcessBrightness();
    });
  }

  Future<void> _captureAndProcessBrightness() async {
    if (_isDisposed || _suspended) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _scheduleNextCheck();
      return;
    }

    try {
      final image = await _cameraController!.takePicture();
      final brightness = await _calculateBrightness(image.path);
      if (_isDisposed) return;

      ingestBrightness(brightness);

      try {
        await File(image.path).delete();
      } catch (_) {}

      _scheduleNextCheck();
    } catch (e) {
      debugPrint("Error calculating brightness: $e");
      _scheduleNextCheck();
    }
  }

  /// Applies one brightness reading. Separated from the camera capture so the
  /// decision — which is where the interesting behaviour is — can be exercised
  /// without a device.
  @visibleForTesting
  void ingestBrightness(double brightness) {
    _updateBrightnessHistory(brightness);
    _updateStabilityStatus();
    _ambientBrightness = brightness;
    _setCameraVisibility(_assessBrightness(brightness));
  }

  /// Maps a brightness reading to a visibility level, or to null when the
  /// reading means the lens is covered rather than the road is dark.
  VisibilityLevel? _assessBrightness(double brightness) {
    if (brightness < pocketBrightnessThreshold) {
      _consecutiveDarkSamples++;
    } else {
      _consecutiveDarkSamples = 0;
    }

    final looksPocketed = _consecutiveDarkSamples >= pocketSampleCount &&
        _vehicleSpeedKph >= pocketMinSpeedKph;

    // A phone face-down in a bag on a motorway is not a reason to recommend
    // 20 km/h. Report that the camera has nothing to say and let the model fall
    // back to solar elevation and weather.
    if (looksPocketed) return null;

    return _mapBrightnessToVisibility(brightness);
  }

  void _setCameraVisibility(VisibilityLevel? level) {
    if (_cameraVisibility == level) return;
    _cameraVisibility = level;
    if (!_isDisposed) notifyListeners();
  }

  void _updateBrightnessHistory(double brightness) {
    _brightnessHistory.add(brightness);
    if (_brightnessHistory.length > _historySize) {
      _brightnessHistory.removeAt(0);
    }
  }

  void _updateStabilityStatus() {
    if (_brightnessHistory.length < 3) {
      _isStable = false;
      _currentIntervalSeconds = _minIntervalSeconds;
      return;
    }

    final recent = _brightnessHistory.sublist(_brightnessHistory.length - 3);
    final avg = recent.reduce((a, b) => a + b) / recent.length;
    if (avg == 0) {
      _isStable = true;
      return;
    }
    final variance =
        recent.map((b) => (b - avg).abs() / avg).reduce((a, b) => a + b) /
            recent.length;

    _isStable = variance < _stabilityThreshold;

    if (_isStable) {
      _currentIntervalSeconds = (_currentIntervalSeconds + 5).clamp(
        _minIntervalSeconds,
        _maxIntervalSeconds,
      );
    } else {
      _currentIntervalSeconds = _minIntervalSeconds;
    }
  }

  VisibilityLevel _mapBrightnessToVisibility(double brightness) {
    if (brightness > 180) return VisibilityLevel.excellent;
    if (brightness > 100) return VisibilityLevel.good;
    if (brightness > 50) return VisibilityLevel.moderate;
    if (brightness > 20) return VisibilityLevel.poor;
    return VisibilityLevel.veryPoor;
  }

  Future<double> _calculateBrightness(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();

      if (bytes.length < 100) return 128;

      final image = img.decodeImage(bytes);
      if (image == null) return 128;

      int total = 0;
      int count = 0;
      int step = (image.width * image.height / 1000).clamp(1, 20).toInt();

      for (int y = 0; y < image.height; y += step) {
        for (int x = 0; x < image.width; x += step) {
          final pixel = image.getPixel(x, y);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();
          total += ((r + g + b) / 3).toInt();
          count++;
        }
      }

      return count > 0 ? total / count : 128;
    } catch (e) {
      return 128;
    }
  }

  /// Records the visibility ceiling the weather implies, independently of what
  /// the camera sees. Kept separate so a camera sample can no longer erase it.
  void updateVisibilityFromWeather(WeatherCondition weather) {
    final assessed = switch (weather) {
      WeatherCondition.clear ||
      WeatherCondition.cloudy =>
        VisibilityLevel.excellent,
      WeatherCondition.rain => VisibilityLevel.good,
      WeatherCondition.heavyRain ||
      WeatherCondition.fog ||
      WeatherCondition.smoke ||
      WeatherCondition.haze ||
      WeatherCondition.snow ||
      WeatherCondition.freezingRain ||
      WeatherCondition.sleet ||
      WeatherCondition.hail ||
      WeatherCondition.dust ||
      WeatherCondition.storm =>
        VisibilityLevel.moderate,
    };

    if (_weatherVisibility == assessed) return;
    _weatherVisibility = assessed;
    if (!_isDisposed) notifyListeners();
  }

  Future<void> _releaseCamera() async {
    _brightnessTimer?.cancel();
    _brightnessTimer = null;
    final controller = _cameraController;
    _cameraController = null;
    _isInitialized = false;
    try {
      await controller?.dispose();
    } catch (e) {
      debugPrint('[VisibilityService] Error disposing camera: $e');
    }
  }

  Future<void> stop() async {
    await _releaseCamera();
    _suspended = false;
    _consecutiveDarkSamples = 0;
    _vehicleSpeedKph = 0;
    _setCameraVisibility(null);
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _brightnessTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }
}
