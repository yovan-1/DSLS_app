import 'package:flutter/material.dart' hide DayPeriod;
import 'package:geolocator/geolocator.dart';
import '../models/speed_calculator.dart';

class AutoParametersService extends ChangeNotifier {
  WeatherCondition _weather = WeatherCondition.clear;
  DayPeriod _timeOfDay = DayPeriod.afternoon;
  LocationType _location = LocationType.urban;
  VisibilityLevel _visibility = VisibilityLevel.excellent;
  final bool _isLoading = false;

  VisibilityLevel? _lastCameraVisibility;
  WeatherCondition? _lastWeather;
  int _contradictionCount = 0;

  WeatherCondition get weather => _weather;
  DayPeriod get timeOfDay => _timeOfDay;
  LocationType get location => _location;
  VisibilityLevel get visibility => _visibility;
  bool get isLoading => _isLoading;
  int get contradictionCount => _contradictionCount;

  void updateTimeOfDay() {
    final nextPeriod = _periodForHour(DateTime.now().hour);
    final previousPeriod = _timeOfDay;
    final previousVisibility = _visibility;

    _timeOfDay = nextPeriod;
    _updateVisibilityFromTime();

    if (previousPeriod != _timeOfDay || previousVisibility != _visibility) {
      notifyListeners();
    }
  }

  DayPeriod _periodForHour(int hour) {
    if (hour >= 5 && hour < 12) return DayPeriod.morning;
    if (hour >= 12 && hour < 17) return DayPeriod.afternoon;
    if (hour >= 17 && hour < 20) return DayPeriod.evening;
    return DayPeriod.night;
  }

  void _updateVisibilityFromTime() {
    switch (_timeOfDay) {
      case DayPeriod.morning:
      case DayPeriod.afternoon:
        if (_visibility != VisibilityLevel.poor &&
            _visibility != VisibilityLevel.veryPoor) {
          _visibility = VisibilityLevel.good;
        }
        break;
      case DayPeriod.evening:
        if (_visibility != VisibilityLevel.veryPoor) {
          _visibility = VisibilityLevel.moderate;
        }
        break;
      case DayPeriod.night:
        _visibility = VisibilityLevel.poor;
        break;
    }
  }

  Future<void> updateLocationType(Position? position) async {
    if (position == null) return;

    final speed = position.speed * 3.6;
    final nextLocation = speed < 30
        ? LocationType.urban
        : (speed < 70 ? LocationType.suburban : LocationType.highway);

    if (nextLocation == _location) return;
    _location = nextLocation;
    notifyListeners();
  }

  void updateWeather(WeatherCondition condition) {
    final previousWeather = _weather;
    final previousVisibility = _visibility;

    _lastWeather = condition;
    _weather = condition;
    _updateVisibilityFromWeather();

    if (previousWeather != _weather || previousVisibility != _visibility) {
      notifyListeners();
    }
  }

  void _updateVisibilityFromWeather() {
    switch (_weather) {
      case WeatherCondition.rain:
      case WeatherCondition.heavyRain:
        _visibility = _lowerVisibility(_visibility, 1);
        break;
      case WeatherCondition.fog:
      case WeatherCondition.smoke:
      case WeatherCondition.haze:
      case WeatherCondition.snow:
      case WeatherCondition.freezingRain:
      case WeatherCondition.sleet:
      case WeatherCondition.hail:
      case WeatherCondition.dust:
      case WeatherCondition.storm:
        _visibility = _lowerVisibility(_visibility, 2);
        break;
      case WeatherCondition.clear:
      case WeatherCondition.cloudy:
        break;
    }
  }

  void updateVisibilityFromCamera(VisibilityLevel cameraVisibility) {
    final previousVisibility = _visibility;
    final previousContradictions = _contradictionCount;
    final previousCameraVisibility = _lastCameraVisibility;
    _lastCameraVisibility = cameraVisibility;

    if (previousCameraVisibility != null && _lastWeather != null) {
      final cameraPoor = cameraVisibility == VisibilityLevel.poor ||
          cameraVisibility == VisibilityLevel.veryPoor;
      final weatherPoor = _weather == WeatherCondition.fog ||
          _weather == WeatherCondition.smoke ||
          _weather == WeatherCondition.haze ||
          _weather == WeatherCondition.rain ||
          _weather == WeatherCondition.heavyRain;

      if (cameraPoor != weatherPoor) {
        _contradictionCount++;
      } else {
        _contradictionCount = 0;
      }
    }

    if (cameraVisibility == VisibilityLevel.poor ||
        cameraVisibility == VisibilityLevel.veryPoor) {
      _visibility = cameraVisibility;
    }

    if (previousVisibility != _visibility ||
        previousContradictions != _contradictionCount) {
      notifyListeners();
    }
  }

  VisibilityLevel _lowerVisibility(VisibilityLevel level, int steps) {
    final values = VisibilityLevel.values;
    final currentIndex = level.index;
    final newIndex = (currentIndex + steps).clamp(0, values.length - 1);
    return values[newIndex];
  }

  void updateVisibility(VisibilityLevel level) {
    if (_visibility == level) return;
    _visibility = level;
    notifyListeners();
  }

  SpeedParameters get currentParams => SpeedParameters(
        weather: _weather,
        timeOfDay: _timeOfDay,
        location: _location,
        visibility: _visibility,
        baseSpeedLimit: 60,
      );
}
