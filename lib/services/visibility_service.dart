import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide DayPeriod;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../models/speed_calculator.dart';

class VisibilityService extends ChangeNotifier {
  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _permissionDenied = false;
  double _ambientBrightness = 128;
  VisibilityLevel _visibilityLevel = VisibilityLevel.good;
  VisibilityLevel _cameraVisibilityLevel = VisibilityLevel.good;
  Timer? _brightnessTimer;
  List<CameraDescription>? _cameras;

  double get ambientBrightness => _ambientBrightness;
  bool get isInitialized => _isInitialized;
  bool get permissionDenied => _permissionDenied;
  VisibilityLevel get visibilityLevel => _visibilityLevel;
  VisibilityLevel get cameraVisibilityLevel => _cameraVisibilityLevel;
  bool get isAvailable => _isInitialized && !_permissionDenied;

  Future<void> initialize() async {
    if (_isInitialized || _permissionDenied) return;

    try {
      var status = await Permission.camera.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        _permissionDenied = true;
        debugPrint("[VisibilityService] Camera permission denied");
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
      _updateVisibilityFromTime();
      notifyListeners();
      _startBrightnessMonitoring();
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  void _startBrightnessMonitoring() {
    _brightnessTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        try {
          final image = await _cameraController!.takePicture();
          final brightness = await _calculateBrightness(image.path);
          final cameraLevel = _mapBrightnessToVisibility(brightness);
          final hasChanged = brightness != _ambientBrightness ||
              cameraLevel != _cameraVisibilityLevel ||
              cameraLevel != _visibilityLevel;

          _ambientBrightness = brightness;
          _cameraVisibilityLevel = cameraLevel;
          _visibilityLevel = cameraLevel;
          await File(image.path).delete();

          if (hasChanged) {
            notifyListeners();
          }
        } catch (e) {
          debugPrint("Error calculating brightness: $e");
        }
      }
    });
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

  void _updateVisibilityFromTime() {
    _visibilityLevel = _timeBasedVisibility();
  }

  VisibilityLevel _timeBasedVisibility() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 18) return VisibilityLevel.good;
    if (hour >= 18 && hour < 20) return VisibilityLevel.moderate;
    return VisibilityLevel.poor;
  }

  VisibilityLevel _baseVisibility() {
    if (_isInitialized && !_permissionDenied) {
      return _cameraVisibilityLevel;
    }
    return _timeBasedVisibility();
  }

  void updateVisibilityFromWeather(WeatherCondition weather) {
    final base = _baseVisibility();

    switch (weather) {
      case WeatherCondition.rain:
        _visibilityLevel = _lowerVisibility(base, 1);
        break;
      case WeatherCondition.heavyRain:
      case WeatherCondition.fog:
      case WeatherCondition.smoke:
      case WeatherCondition.haze:
      case WeatherCondition.snow:
      case WeatherCondition.freezingRain:
      case WeatherCondition.sleet:
      case WeatherCondition.hail:
      case WeatherCondition.dust:
      case WeatherCondition.storm:
        _visibilityLevel = _lowerVisibility(base, 2);
        break;
      case WeatherCondition.clear:
      case WeatherCondition.cloudy:
        _visibilityLevel = base;
        break;
    }
    notifyListeners();
  }

  void updateFromCameraOverride() {
    if (_cameraVisibilityLevel == VisibilityLevel.poor ||
        _cameraVisibilityLevel == VisibilityLevel.veryPoor) {
      _visibilityLevel = _cameraVisibilityLevel;
      notifyListeners();
    }
  }

  VisibilityLevel _lowerVisibility(VisibilityLevel level, int steps) {
    final values = VisibilityLevel.values;
    final currentIndex = level.index;
    final newIndex = (currentIndex + steps).clamp(0, values.length - 1);
    return values[newIndex];
  }

  @override
  void dispose() {
    _brightnessTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }
}