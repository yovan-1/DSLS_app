import 'dart:async';

import 'package:dsls_app/models/speed_calculator.dart'
    show LocationType, VisibilityLevel, WeatherCondition;
import 'package:dsls_app/models/speed_model/road_conditions.dart';
import 'package:dsls_app/models/speed_model/solar_position.dart';
import 'package:dsls_app/models/speed_model/speed_advisor.dart';
import 'package:dsls_app/models/weather_data.dart';
import 'package:dsls_app/services/alert_service.dart';
import 'package:dsls_app/services/drive_foreground_service.dart';
import 'package:dsls_app/services/driving_session_coordinator.dart';
import 'package:dsls_app/services/screen_wake_controller.dart';
import 'package:dsls_app/services/gps_speed_service.dart';
import 'package:dsls_app/services/location_speed_service.dart';
import 'package:dsls_app/services/motion_sensor_service.dart';
import 'package:dsls_app/services/speed_service.dart';
import 'package:dsls_app/services/trip_service.dart';
import 'package:dsls_app/services/visibility_service.dart';
import 'package:dsls_app/services/weather_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Note the absence of `TestWidgetsFlutterBinding.ensureInitialized()` in this
/// file. That is the point of the whole phase: a driving session must run with
/// no widget tree and no Flutter binding at all. If someone reintroduces a
/// dependency on either, these tests stop compiling or throw.

Position _fixAt(double lat, double lon, {double speedMps = 0}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: speedMps,
    speedAccuracy: 1,
  );
}

/// A GPS service whose stream and speed readings are driven by the test rather
/// than by the platform.
class FakeGpsService extends GpsSpeedService {
  final _controller = StreamController<SpeedUpdate>.broadcast();
  int scriptedSpeed = 0;
  bool tracking = false;
  RoadConditions? lastConditions;

  @override
  Stream<SpeedUpdate> get speedStream => _controller.stream;

  @override
  bool get isTracking => tracking;

  @override
  int get fusedSpeed => scriptedSpeed;

  @override
  int get smoothedSpeed => scriptedSpeed;

  @override
  RiskData? get cachedRiskData => lastConditions == null
      ? null
      : RiskData(recommendation: SpeedAdvisor.evaluate(lastConditions!));

  @override
  void setRoadConditions(RoadConditions conditions) {
    lastConditions = conditions;
  }

  @override
  void updateFromAccelerometer(double speedMps) {}

  @override
  Future<void> startTracking() async {
    tracking = true;
  }

  @override
  Future<void> stopTracking() async {
    tracking = false;
  }

  /// Emits a fix at [speedKph], as the real service does on every position.
  void emit(double lat, double lon, int speedKph) {
    scriptedSpeed = speedKph;
    _controller.add(
      SpeedUpdate(
        rawGpsSpeed: speedKph,
        smoothedSpeed: speedKph,
        fusedSpeed: speedKph,
        timestamp: DateTime.now(),
        position: _fixAt(lat, lon, speedMps: speedKph / 3.6),
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }
}

/// Stands in for a permission denial: tracking never comes up.
class RefusingGpsService extends FakeGpsService {
  @override
  String? get errorMessage => 'Location permissions are denied';

  @override
  Future<void> startTracking() async {
    tracking = false;
  }
}

/// Lets a test place the driver in or out of a zone without depending on the
/// real Mbarara geodata.
class FakeSpeedService extends SpeedService {
  LocationSpeedResult scriptedLocation = LocationSpeedResult.defaultResult;
  int updatePositionCalls = 0;
  VisibilityLevel? camera;

  @override
  LocationSpeedResult get locationResult => scriptedLocation;

  @override
  RoadConditions get conditions => RoadConditions(
        speedLimitKph: scriptedLocation.speedLimit,
        limitSource: scriptedLocation.limitSource,
        roadClass: scriptedLocation.locationType,
        weather: WeatherCondition.clear,
        daylight: DaylightState.daylight,
        cameraVisibility: camera,
      );

  @override
  Future<void> updatePosition(
    double lat,
    double lon, {
    double speedKph = 0,
  }) async {
    updatePositionCalls++;
    lastSpeedKph = speedKph;
  }

  double lastSpeedKph = 0;

  @override
  void updateWeather(WeatherCondition weather) {}

  @override
  void updateVisibility(VisibilityLevel? visibility) {
    camera = visibility;
  }
}

class RecordingAlertService extends SpeedAlertService {
  int overSpeedAlerts = 0;
  int zoneAlerts = 0;
  final List<bool> zoneApproaching = [];

  @override
  Future<void> triggerAlert(int currentSpeed, int recommendedSpeed) async {
    overSpeedAlerts++;
  }

  @override
  Future<void> triggerZoneAlert({
    required LocationType zoneType,
    required String zoneName,
    required int speedLimit,
    required bool isApproaching,
  }) async {
    zoneAlerts++;
    zoneApproaching.add(isApproaching);
  }

  @override
  void resetAlertState() {}
}

class StubVisibilityService extends VisibilityService {
  bool suspended = false;
  bool resumed = false;
  int lastReportedSpeed = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> suspend() async {
    suspended = true;
  }

  @override
  Future<void> resume() async {
    resumed = true;
    suspended = false;
  }

  @override
  void updateVehicleSpeed(int speedKph) {
    lastReportedSpeed = speedKph;
  }

  @override
  void updateVisibilityFromWeather(WeatherCondition weather) {}
}

class StubMotionService extends MotionSensorService {
  @override
  Future<void> initialize() async {}

  @override
  bool get isInitialized => false;

  @override
  void stop() {}
}

class RecordingForegroundService implements DriveForegroundService {
  bool running = false;
  int startCount = 0;
  int stopCount = 0;
  String lastText = '';

  @override
  Future<void> start({required String title, required String text}) async {
    running = true;
    startCount++;
    lastText = text;
  }

  @override
  Future<void> update({required String title, required String text}) async {
    if (!running) return;
    lastText = text;
  }

  @override
  Future<void> stop() async {
    running = false;
    stopCount++;
  }
}

class RecordingWakeController implements ScreenWakeController {
  @override
  bool enabled = true;

  bool held = false;

  @override
  Future<void> apply({
    required bool sessionActive,
    required bool foregrounded,
  }) async {
    held = enabled && sessionActive && foregrounded;
  }

  @override
  Future<void> release() async {
    held = false;
  }
}

class StubWeatherService implements WeatherService {
  int calls = 0;

  @override
  bool get isEnabled => true;

  @override
  String get providerName => 'stub';

  @override
  Future<WeatherData> getWeather(double latitude, double longitude) async {
    calls++;
    return WeatherData(
      condition: WeatherCondition.clear,
      temperature: 22,
      description: 'clear',
      humidity: 50,
      windSpeed: 3,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<WeatherData> getWeatherByLocation(String location) =>
      getWeather(0, 0);
}

void main() {
  late FakeGpsService gps;
  late FakeSpeedService speed;
  late TripService trips;
  late RecordingAlertService alerts;
  late StubVisibilityService visibility;
  late RecordingForegroundService foreground;
  late RecordingWakeController wake;
  late DrivingSessionCoordinator coordinator;

  setUp(() {
    gps = FakeGpsService();
    speed = FakeSpeedService();
    trips = TripService();
    alerts = RecordingAlertService();
    visibility = StubVisibilityService();
    foreground = RecordingForegroundService();
    wake = RecordingWakeController();
    coordinator = DrivingSessionCoordinator(
      gps: gps,
      speed: speed,
      trips: trips,
      alerts: alerts,
      visibility: visibility,
      motion: StubMotionService(),
      weather: StubWeatherService(),
      foreground: foreground,
      wakeController: wake,
    );
  });

  tearDown(() async {
    await coordinator.stop();
    coordinator.dispose();
  });

  /// Lets the stream deliver and the coordinator's handler run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('session lifecycle', () {
    test('runs with no widget tree present', () async {
      final started = await coordinator.start();

      expect(started, isTrue);
      expect(coordinator.isActive, isTrue);
      expect(gps.isTracking, isTrue);
      expect(trips.isTracking, isTrue);
    });

    test('start reports failure when GPS will not start', () async {
      final deadGps = RefusingGpsService();
      final stalled = DrivingSessionCoordinator(
        gps: deadGps,
        speed: speed,
        trips: TripService(),
        alerts: alerts,
        visibility: StubVisibilityService(),
        motion: StubMotionService(),
        weather: StubWeatherService(),
      );
      addTearDown(stalled.dispose);

      final started = await stalled.start();

      expect(started, isFalse);
      expect(stalled.isActive, isFalse);
      expect(stalled.state.errorMessage, 'Location permissions are denied');
    });

    test('stop tears down GPS and the trip together', () async {
      await coordinator.start();
      gps.emit(0.6, 30.6, 40);
      await settle();

      await coordinator.stop();

      expect(coordinator.isActive, isFalse);
      expect(gps.isTracking, isFalse);
      expect(trips.isTracking, isFalse);
    });

    test('ignores fixes that arrive after stop', () async {
      await coordinator.start();
      await coordinator.stop();

      gps.emit(0.6, 30.6, 200);
      await settle();

      expect(speed.updatePositionCalls, 0);
    });
  });

  group('over-speed alerts are edge-triggered', () {
    test('a sustained overspeed raises exactly one alert', () async {
      await coordinator.start();

      // 60 km/h zone, driver holds 120 across twenty consecutive fixes.
      for (var i = 0; i < 20; i++) {
        gps.emit(0.6, 30.6, 120);
        await settle();
      }

      expect(alerts.overSpeedAlerts, 1,
          reason: 'the tick is not the event — one crossing is one alert');
    });

    test('dropping back and going over again raises a second alert', () async {
      await coordinator.start();

      gps.emit(0.6, 30.6, 120);
      await settle();
      gps.emit(0.6, 30.6, 20);
      await settle();
      gps.emit(0.6, 30.6, 120);
      await settle();

      expect(alerts.overSpeedAlerts, 2);
    });

    test('staying under the limit raises none', () async {
      await coordinator.start();

      for (var i = 0; i < 5; i++) {
        gps.emit(0.6, 30.6, 10);
        await settle();
      }

      expect(alerts.overSpeedAlerts, 0);
    });
  });

  group('zone alerts are independent of over-speed', () {
    test('a zone alert fires even while the driver is over the limit',
        () async {
      speed.scriptedLocation = const LocationSpeedResult(
        locationType: LocationType.schoolZone,
        speedLimit: 30,
        activeZoneName: 'Mbarara Primary',
        activeRoadName: '',
        status: LocationSpeedStatus.approachingZone,
      );
      await coordinator.start();

      gps.emit(0.6, 30.6, 120);
      await settle();

      expect(alerts.overSpeedAlerts, 1);
      expect(alerts.zoneAlerts, 1,
          reason: 'approaching a school zone too fast is when it matters most');
      expect(alerts.zoneApproaching.single, isTrue);
    });

    test('entering a zone reports as not-approaching', () async {
      speed.scriptedLocation = const LocationSpeedResult(
        locationType: LocationType.schoolZone,
        speedLimit: 30,
        activeZoneName: 'Mbarara Primary',
        activeRoadName: '',
        status: LocationSpeedStatus.inZone,
      );
      await coordinator.start();

      gps.emit(0.6, 30.6, 20);
      await settle();

      expect(alerts.zoneAlerts, 1);
      expect(alerts.zoneApproaching.single, isFalse);
    });

    test('no zone alert outside a zone', () async {
      await coordinator.start();

      gps.emit(0.6, 30.6, 20);
      await settle();

      expect(alerts.zoneAlerts, 0);
    });
  });

  group('trip recording is decoupled from the fix rate', () {
    test('a burst of fixes produces one record, not one per fix', () async {
      await coordinator.start();

      for (var i = 0; i < 20; i++) {
        gps.emit(0.6, 30.6, 50);
        await settle();
      }

      expect(trips.drivingRecords.length, 1,
          reason: 'records are sampled on a clock, not on GPS arrival');
    });

    test('a sustained overspeed counts as one episode', () async {
      await coordinator.start();

      for (var i = 0; i < 20; i++) {
        gps.emit(0.6, 30.6, 120);
        await settle();
      }

      expect(trips.currentTrip?.overSpeedCount, 1);
    });
  });

  group('weather', () {
    test('is fetched once for a burst of fixes', () async {
      final weather = StubWeatherService();
      final c = DrivingSessionCoordinator(
        gps: gps,
        speed: speed,
        trips: trips,
        alerts: alerts,
        visibility: StubVisibilityService(),
        motion: StubMotionService(),
        weather: weather,
      );
      addTearDown(c.dispose);
      await c.start();

      for (var i = 0; i < 10; i++) {
        gps.emit(0.6, 30.6, 50);
        await settle();
      }
      await settle();

      expect(weather.calls, 1);
      await c.stop();
    });
  });

  group('app lifecycle', () {
    test('backgrounding releases the camera and blanks the reading', () async {
      await coordinator.start();
      gps.emit(0.6, 30.6, 90);
      await settle();

      // The camera had a reading before the app went away.
      speed.updateVisibility(VisibilityLevel.veryPoor);
      expect(coordinator.state.conditions.cameraVisibility,
          VisibilityLevel.veryPoor);

      await coordinator.onAppPaused();

      expect(visibility.suspended, isTrue,
          reason: 'a pocketed phone cannot measure ambient light');
      expect(coordinator.state.conditions.cameraVisibility, isNull,
          reason: 'better unknown than a stale reading presented as current');
    });

    test('returning to the foreground re-acquires the camera', () async {
      await coordinator.start();
      await coordinator.onAppPaused();

      await coordinator.onAppResumed();

      expect(visibility.resumed, isTrue);
    });

    test('lifecycle events do nothing when no drive is running', () async {
      await coordinator.onAppPaused();

      expect(visibility.suspended, isFalse);
    });

    test('the vehicle speed reaches the pocket detector', () async {
      await coordinator.start();

      gps.emit(0.6, 30.6, 95);
      await settle();

      expect(visibility.lastReportedSpeed, 95);
    });
  });

  group('surviving the screen lock', () {
    test('starting a drive starts the foreground service', () async {
      await coordinator.start();

      expect(foreground.running, isTrue,
          reason: 'without it Android trims the process and the drive ends');
    });

    test('stopping a drive stops the foreground service', () async {
      await coordinator.start();

      await coordinator.stop();

      expect(foreground.running, isFalse);
      expect(foreground.stopCount, 1);
    });

    test('the service keeps running while the app is backgrounded', () async {
      await coordinator.start();

      await coordinator.onAppPaused();

      expect(foreground.running, isTrue,
          reason: 'the locked screen is exactly what it is there for');
    });

    test('the notification carries the current figures', () async {
      await coordinator.start();
      gps.emit(0.6, 30.6, 72);
      await settle();

      expect(foreground.lastText, contains('72 km/h'));
      expect(foreground.lastText, contains('recommended'));
    });

    test('a failed start does not leave a service running', () async {
      final deadGps = RefusingGpsService();
      final orphaned = RecordingForegroundService();
      final stalled = DrivingSessionCoordinator(
        gps: deadGps,
        speed: speed,
        trips: TripService(),
        alerts: alerts,
        visibility: StubVisibilityService(),
        motion: StubMotionService(),
        weather: StubWeatherService(),
        foreground: orphaned,
      );
      addTearDown(stalled.dispose);

      await stalled.start();

      expect(orphaned.running, isFalse);
    });
  });

  group('screen wakelock', () {
    test('is held while driving in the foreground', () async {
      await coordinator.start();

      expect(wake.held, isTrue);
    });

    test('is released when the app is backgrounded', () async {
      await coordinator.start();

      await coordinator.onAppPaused();

      expect(wake.held, isFalse,
          reason: 'holding a screen nobody can see is pure battery drain');
    });

    test('is re-taken when the app returns', () async {
      await coordinator.start();
      await coordinator.onAppPaused();

      await coordinator.onAppResumed();

      expect(wake.held, isTrue);
    });

    test('is released when the drive ends', () async {
      await coordinator.start();

      await coordinator.stop();

      expect(wake.held, isFalse);
    });

    test('is not taken when the user has turned it off', () async {
      wake.enabled = false;

      await coordinator.start();

      expect(wake.held, isFalse);
    });

    test('can be turned off mid-drive', () async {
      await coordinator.start();
      expect(wake.held, isTrue);

      await coordinator.setKeepScreenOn(false);

      expect(wake.held, isFalse);
      expect(coordinator.keepScreenOn, isFalse);
    });

    test('turning it off does not stop the drive', () async {
      await coordinator.start();

      await coordinator.setKeepScreenOn(false);

      expect(coordinator.isActive, isTrue);
      expect(foreground.running, isTrue);
    });
  });

  group('state snapshot', () {
    test('reports over-speed and the difference', () async {
      await coordinator.start();
      gps.emit(0.6, 30.6, 100);
      await settle();

      final state = coordinator.state;
      expect(state.isActive, isTrue);
      expect(state.speedKph, 100);
      expect(state.isOverSpeed, isTrue);
      expect(state.overSpeedDiff, 100 - state.recommendedSpeedKph);
    });

    test('is not stale immediately after a fix', () async {
      await coordinator.start();
      gps.emit(0.6, 30.6, 50);
      await settle();

      expect(coordinator.state.isStale, isFalse);
    });

    test('is stale before any fix arrives', () async {
      await coordinator.start();

      expect(coordinator.state.isStale, isTrue);
    });

    test('an inactive session is never stale', () {
      expect(coordinator.state.isStale, isFalse);
    });
  });
}
