import 'package:flutter/material.dart' hide TimeOfDay, DayPeriod;
import '../models/speed_calculator.dart';
import 'location_speed_service.dart';
import '../data/speed_zones.dart';
import '../data/roads.dart';

class SpeedService extends ChangeNotifier {
  SpeedParameters _currentParams = SpeedParameters.defaults();
  bool _isMonitoring = false;
  int _currentSpeed = 0;
  final LocationSpeedService _locationSpeedService = LocationSpeedService();
  bool _locationServiceInitialized = false;

  SpeedService() {
    _initializeLocationService();
  }

  SpeedParameters get currentParams => _currentParams;
  bool get isMonitoring => _isMonitoring;
  int get currentSpeed => _currentSpeed;
  LocationSpeedService get locationService => _locationSpeedService;
  bool get locationServiceInitialized => _locationServiceInitialized;

  LocationSpeedResult get locationResult =>
      _locationSpeedService.currentResult;
  bool get isApproachingZone => 
      _locationSpeedService.status == LocationSpeedStatus.approachingZone ||
      _locationSpeedService.status == LocationSpeedStatus.inZone;

  void _initializeLocationService() {
    _locationSpeedService.initialize(mbararaSpeedZones, mbararaRoads);
    _locationServiceInitialized = true;
  }

  void updatePosition(double lat, double lon) {
    _locationSpeedService.updatePosition(lat, lon);
    
    final result = _locationSpeedService.currentResult;
    if (result.status != LocationSpeedStatus.none) {
      _currentParams = SpeedParameters(
        weather: _currentParams.weather,
        timeOfDay: _currentParams.timeOfDay,
        location: result.locationType,
        visibility: _currentParams.visibility,
        baseSpeedLimit: result.speedLimit,
      );
    }
    notifyListeners();
  }

  SpeedCalculationResult get calculationResult =>
      SpeedCalculator.calculate(_currentParams);

  void updateWeather(WeatherCondition weather) {
    _currentParams = SpeedParameters(
      weather: weather,
      timeOfDay: _currentParams.timeOfDay,
      location: _currentParams.location,
      visibility: _currentParams.visibility,
      baseSpeedLimit: _currentParams.baseSpeedLimit,
    );
    notifyListeners();
  }

  void updateTimeOfDay(DayPeriod time) {
    _currentParams = SpeedParameters(
      weather: _currentParams.weather,
      timeOfDay: time,
      location: _currentParams.location,
      visibility: _currentParams.visibility,
      baseSpeedLimit: _currentParams.baseSpeedLimit,
    );
    notifyListeners();
  }

  void updateLocation(LocationType location) {
    _currentParams = SpeedParameters(
      weather: _currentParams.weather,
      timeOfDay: _currentParams.timeOfDay,
      location: location,
      visibility: _currentParams.visibility,
      baseSpeedLimit: _currentParams.baseSpeedLimit,
    );
    notifyListeners();
  }

  void updateVisibility(VisibilityLevel visibility) {
    _currentParams = SpeedParameters(
      weather: _currentParams.weather,
      timeOfDay: _currentParams.timeOfDay,
      location: _currentParams.location,
      visibility: visibility,
      baseSpeedLimit: _currentParams.baseSpeedLimit,
    );
    notifyListeners();
  }

  void updateBaseSpeed(int speed) {
    _currentParams = SpeedParameters(
      weather: _currentParams.weather,
      timeOfDay: _currentParams.timeOfDay,
      location: _currentParams.location,
      visibility: _currentParams.visibility,
      baseSpeedLimit: speed,
    );
    notifyListeners();
  }

  void setMonitoring(bool value) {
    _isMonitoring = value;
    notifyListeners();
  }

  void updateCurrentSpeed(int speed) {
    _currentSpeed = speed;
    notifyListeners();
  }

  void reset() {
    _currentParams = SpeedParameters.defaults();
    _isMonitoring = false;
    _currentSpeed = 0;
    notifyListeners();
  }
}
