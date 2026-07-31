import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/dashboard.dart';
import 'services/trip_service.dart';
import 'services/speed_service.dart';
import 'services/alert_service.dart';
import 'services/gps_speed_service.dart';
import 'services/drive_foreground_service.dart';
import 'services/driving_session_coordinator.dart';
import 'services/screen_wake_controller.dart';
import 'services/visibility_service.dart';
import 'services/offline_storage_service.dart';
import 'services/motion_sensor_service.dart';
import 'services/settings_service.dart';
import 'services/cloud_upload_service.dart';
import 'widgets/app_lifecycle_observer.dart';
import 'widgets/error_boundary.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  ErrorWidget.builder = (details) => AppErrorScreen(
        error: details.exception,
        onRestart: () {
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const Dashboard()),
            (route) => false,
          );
        },
      );

  runZonedGuarded(() async {
    final storage = OfflineStorageService();
    await storage.init();

    final settingsService = SettingsService();
    await settingsService.init();

    final cloudUploadService = CloudUploadService(settingsService: settingsService);

    final alertService = SpeedAlertService(settingsService: settingsService);
    await alertService.init();

    final tripService = TripService();
    tripService.setStorage(storage);
    tripService.setCloudUploadService(cloudUploadService);
    tripService.setSettingsService(settingsService);
    await tripService.loadTrips();

    // Built here rather than with lazy `create:` providers so that construction
    // order is explicit and the coordinator can hold direct references — its
    // lifetime has to be independent of any widget, since the whole point is
    // that a drive survives the screen going away.
    final speedService = SpeedService();
    final gpsService = GpsSpeedService();
    final visibilityService = VisibilityService();
    final motionService = MotionSensorService();

    final sessionCoordinator = DrivingSessionCoordinator(
      gps: gpsService,
      speed: speedService,
      trips: tripService,
      alerts: alertService,
      visibility: visibilityService,
      motion: motionService,
      foreground: PlatformDriveForegroundService(),
      wakeController: PlatformScreenWakeController(
        enabled: settingsService.keepScreenOn,
      ),
    );

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settingsService),
          ChangeNotifierProvider.value(value: tripService),
          ChangeNotifierProvider.value(value: cloudUploadService),
          ChangeNotifierProvider.value(value: alertService),
          ChangeNotifierProvider.value(value: speedService),
          ChangeNotifierProvider.value(value: gpsService),
          ChangeNotifierProvider.value(value: visibilityService),
          ChangeNotifierProvider.value(value: motionService),
          ChangeNotifierProvider.value(value: sessionCoordinator),
        ],
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('[Uncaught] $error');
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final coordinator = context.read<DrivingSessionCoordinator>();

    return AppLifecycleObserver(
      onPaused: coordinator.onAppPaused,
      onResumed: coordinator.onAppResumed,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Dynamic Speed',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00C853),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF6F7F9),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF111827),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
