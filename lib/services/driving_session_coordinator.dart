import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/speed_calculator.dart' show SpeedCalculator;
import '../models/speed_model/road_conditions.dart';
import '../models/speed_model/speed_advisor.dart';
import '../models/speed_model/speed_recommendation.dart';
import 'alert_service.dart';
import 'gps_speed_service.dart';
import 'location_speed_service.dart';
import 'motion_sensor_service.dart';
import 'speed_service.dart';
import 'trip_service.dart';
import 'visibility_service.dart';
import 'weather_service.dart';

/// Immutable snapshot of the current drive, for the UI to render.
///
/// The screen used to derive all of this itself from five separately-watched
/// services, which is why it needed post-frame callbacks to keep them in step.
/// One snapshot, updated in one place, removes that class of bug.
@immutable
class DrivingSessionState {
  final bool isActive;
  final int speedKph;
  final SpeedRecommendation recommendation;
  final RoadConditions conditions;
  final LocationSpeedResult locationResult;
  final GpsStatus gpsStatus;
  final String weatherStatus;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? lastFixAt;

  const DrivingSessionState({
    required this.isActive,
    required this.speedKph,
    required this.recommendation,
    required this.conditions,
    required this.locationResult,
    required this.gpsStatus,
    required this.weatherStatus,
    this.errorMessage,
    this.startedAt,
    this.lastFixAt,
  });

  int get recommendedSpeedKph => recommendation.recommendedSpeedKph;
  bool get isOverSpeed => isActive && speedKph > recommendedSpeedKph;
  int get overSpeedDiff => speedKph - recommendedSpeedKph;

  /// True when the session is running but no fix has arrived recently. The UI
  /// should say so rather than presenting a stale speed as current.
  bool get isStale {
    if (!isActive) return false;
    final last = lastFixAt;
    if (last == null) return true;
    return DateTime.now().difference(last) > DrivingSessionCoordinator.staleAfter;
  }
}

/// Owns a driving session: the GPS subscription, zone matching, weather
/// refresh, alert dispatch and trip recording.
///
/// This used to be a `Timer.periodic(500ms)` inside `_SpeedScreenState`, which
/// meant monitoring ended whenever the widget did — a locked screen stopped the
/// drive. It also meant the tick *was* the event: alerts and trip records were
/// emitted per sample rather than per thing-that-happened.
///
/// Here the loop is driven by [GpsSpeedService.speedStream] — positions arrive
/// when they arrive — and the periodic timer is demoted to a heartbeat used
/// only for staleness detection and UI ticking.
///
/// Services are injected rather than read from a `BuildContext` so the whole
/// session can be exercised in tests with no widget tree present.
class DrivingSessionCoordinator extends ChangeNotifier {
  final GpsSpeedService _gps;
  final SpeedService _speed;
  final TripService _trips;
  final SpeedAlertService _alerts;
  final VisibilityService _visibility;
  final MotionSensorService _motion;
  final WeatherService _weather;

  /// No fix for this long and the displayed speed is no longer trustworthy.
  static const staleAfter = Duration(seconds: 5);

  /// Weather changes far more slowly than position, and the provider is a free
  /// public endpoint. One fetch per half hour is plenty.
  static const weatherMaxAge = Duration(minutes: 30);

  /// Trip records are sampled on a clock so that trip statistics describe the
  /// drive rather than the fix rate of whatever device it ran on.
  static const recordInterval = Duration(seconds: 1);

  static const _heartbeatInterval = Duration(seconds: 1);

  StreamSubscription<SpeedUpdate>? _speedSubscription;
  Timer? _heartbeat;

  bool _isActive = false;
  bool _disposed = false;
  DateTime? _startedAt;
  DateTime? _lastFixAt;
  DateTime? _lastRecordAt;
  DateTime? _lastWeatherFetch;
  bool _weatherFetchInProgress = false;
  String _weatherStatus = 'Weather will update after GPS starts';
  String? _errorMessage;

  /// Over-speed is an edge, not a level. Without this the alert would be
  /// re-triggered on every fix for as long as the driver stayed over.
  bool _wasOverSpeed = false;

  DrivingSessionCoordinator({
    required GpsSpeedService gps,
    required SpeedService speed,
    required TripService trips,
    required SpeedAlertService alerts,
    required VisibilityService visibility,
    required MotionSensorService motion,
    WeatherService? weather,
  })  : _gps = gps,
        _speed = speed,
        _trips = trips,
        _alerts = alerts,
        _visibility = visibility,
        _motion = motion,
        _weather = weather ?? WttrInWeatherService();

  bool get isActive => _isActive;

  DrivingSessionState get state {
    final conditions = _speed.conditions;
    return DrivingSessionState(
      isActive: _isActive,
      speedKph: _currentSpeedKph,
      recommendation:
          _gps.cachedRiskData?.recommendation ?? SpeedAdvisor.evaluate(conditions),
      conditions: conditions,
      locationResult: _speed.locationResult,
      gpsStatus: _gps.gpsStatus,
      weatherStatus: _weatherStatus,
      errorMessage: _errorMessage ?? _gps.errorMessage,
      startedAt: _startedAt,
      lastFixAt: _lastFixAt,
    );
  }

  int get _currentSpeedKph =>
      _gps.fusedSpeed > 0 ? _gps.fusedSpeed : _gps.smoothedSpeed;

  /// Starts a drive. Returns false if GPS could not be started, in which case
  /// [DrivingSessionState.errorMessage] explains why.
  Future<bool> start() async {
    if (_isActive) return true;

    _errorMessage = null;
    await _gps.startTracking();
    if (!_gps.isTracking) {
      _errorMessage = _gps.errorMessage ?? 'Could not start location tracking';
      _safeNotify();
      return false;
    }

    _isActive = true;
    _startedAt = DateTime.now();
    _lastFixAt = null;
    _lastRecordAt = null;
    _wasOverSpeed = false;

    _alerts.resetAlertState();
    _trips.startTrip(_speed.conditions);
    _gps.setRoadConditions(_speed.conditions);

    // Both are best-effort: a device with no camera or no sensors still gets a
    // usable session, just with fewer inputs to the model.
    unawaited(_initVisibility());
    unawaited(_motion.initialize());

    _speedSubscription = _gps.speedStream.listen(_onSpeedUpdate);
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) => _onHeartbeat());

    _safeNotify();
    return true;
  }

  Future<void> stop() async {
    if (!_isActive) return;
    _isActive = false;

    await _speedSubscription?.cancel();
    _speedSubscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;

    // The screen used to cancel only its own timer, leaving GPS, camera and
    // sensors running. One owner, one teardown.
    await _gps.stopTracking();
    await _visibility.stop();
    _motion.stop();
    await _trips.endTrip();

    _speed.updateVisibility(null);
    _startedAt = null;
    _lastFixAt = null;
    _wasOverSpeed = false;

    _safeNotify();
  }

  Future<void> _initVisibility() async {
    await _visibility.initialize();
    if (_disposed || !_isActive) return;
    if (!_visibility.isInitialized) return;
    _speed.updateVisibility(_visibility.visibilityLevel);
    _gps.setRoadConditions(_speed.conditions);
    _safeNotify();
  }

  void _onSpeedUpdate(SpeedUpdate update) {
    if (_disposed || !_isActive) return;

    final position = update.position;
    if (position == null) return;

    _lastFixAt = update.timestamp;

    if (_motion.isInitialized) {
      _gps.updateFromAccelerometer(_motion.speedEstimateMps);
    }

    // Zone matching and the solar daylight state both hang off position, so
    // this has to happen before the conditions are handed to the model.
    _speed.updatePosition(position.latitude, position.longitude);
    unawaited(_refreshWeatherIfStale(position.latitude, position.longitude));
    _gps.setRoadConditions(_speed.conditions);

    final speed = _currentSpeedKph;
    final risk = _gps.cachedRiskData;
    final recommendation =
        risk?.recommendation ?? SpeedAdvisor.evaluate(_speed.conditions);

    _dispatchAlerts(speed, recommendation.recommendedSpeedKph);
    _recordIfDue(speed, recommendation);

    _safeNotify();
  }

  /// Over-speed fires once per episode. [SpeedAlertService] has its own
  /// cooldown for a sustained overspeed; this only stops the same crossing
  /// being re-reported on every fix.
  void _dispatchAlerts(int speed, int recommendedSpeed) {
    final isOverSpeed = speed > recommendedSpeed;
    if (isOverSpeed && !_wasOverSpeed) {
      unawaited(_alerts.triggerAlert(speed, recommendedSpeed));
    }
    _wasOverSpeed = isOverSpeed;

    // Zone alerts are deliberately independent of the over-speed branch:
    // approaching a school zone too fast is exactly when the zone alert matters
    // most, and it used to be suppressed in that case.
    final location = _speed.locationResult;
    switch (location.status) {
      case LocationSpeedStatus.approachingZone:
        unawaited(_alerts.triggerZoneAlert(
          zoneType: location.locationType,
          zoneName: location.activeZoneName,
          speedLimit: location.speedLimit,
          isApproaching: true,
        ));
      case LocationSpeedStatus.inZone:
        unawaited(_alerts.triggerZoneAlert(
          zoneType: location.locationType,
          zoneName: location.activeZoneName,
          speedLimit: location.speedLimit,
          isApproaching: false,
        ));
      case LocationSpeedStatus.onRoad:
      case LocationSpeedStatus.none:
        break;
    }
  }

  void _recordIfDue(int speed, SpeedRecommendation recommendation) {
    final now = DateTime.now();
    final last = _lastRecordAt;
    if (last != null && now.difference(last) < recordInterval) return;
    _lastRecordAt = now;

    _trips.addRecord(
      speed: speed,
      recommendedSpeed: recommendation.recommendedSpeedKph,
      riskBand: recommendation.riskBand,
    );
  }

  /// Ticks the UI and lets it notice a stale fix. Deliberately does no driving
  /// logic — that is what made the old 500 ms timer the event source.
  void _onHeartbeat() {
    if (_disposed || !_isActive) return;
    if (!_gps.isTracking) {
      unawaited(stop());
      return;
    }
    _safeNotify();
  }

  Future<void> _refreshWeatherIfStale(double latitude, double longitude) async {
    final last = _lastWeatherFetch;
    final fresh = last != null && DateTime.now().difference(last) < weatherMaxAge;
    if (_weatherFetchInProgress || fresh) return;

    _weatherFetchInProgress = true;
    _weatherStatus = 'Updating weather...';
    _safeNotify();

    try {
      final weather = await _weather.getWeather(latitude, longitude);
      if (_disposed) return;
      _speed.updateWeather(weather.condition);
      _visibility.updateVisibilityFromWeather(weather.condition);
      _gps.setRoadConditions(_speed.conditions);
      _lastWeatherFetch = DateTime.now();
      _weatherStatus =
          '${SpeedCalculator.getWeatherLabel(weather.condition)} • '
          '${weather.temperature.toStringAsFixed(0)}°C';
    } catch (_) {
      if (_disposed) return;
      _weatherStatus = 'Weather unavailable, using safe defaults';
    } finally {
      _weatherFetchInProgress = false;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _speedSubscription?.cancel();
    _heartbeat?.cancel();
    super.dispose();
  }
}
