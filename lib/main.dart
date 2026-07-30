import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/dashboard.dart';
import 'services/trip_service.dart';
import 'services/speed_service.dart';
import 'services/alert_service.dart';
import 'services/gps_speed_service.dart';
import 'services/auto_parameters_service.dart';
import 'services/visibility_service.dart';
import 'services/offline_storage_service.dart';
import 'services/motion_sensor_service.dart';
import 'services/settings_service.dart';
import 'services/cloud_upload_service.dart';
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

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settingsService),
          ChangeNotifierProvider.value(value: tripService),
          ChangeNotifierProvider.value(value: cloudUploadService),
          ChangeNotifierProvider.value(value: alertService),
          ChangeNotifierProvider(create: (_) => SpeedService()),
          ChangeNotifierProvider(create: (_) => GpsSpeedService()),
          ChangeNotifierProvider(create: (_) => AutoParametersService()),
          ChangeNotifierProvider(create: (_) => VisibilityService()),
          ChangeNotifierProvider(create: (_) => MotionSensorService()),
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
    return MaterialApp(
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
    );
  }
}
