import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'services/trip_service.dart';
import 'services/speed_service.dart';
import 'services/alert_service.dart';
import 'services/gps_speed_service.dart';
import 'services/auto_parameters_service.dart';
import 'services/visibility_service.dart';
import 'services/offline_storage_service.dart';
import 'services/route_service.dart';
import 'services/motion_sensor_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final storage = OfflineStorageService();
  await storage.init();
  
  final tripService = TripService();
  tripService.setStorage(storage);
  await tripService.loadTrips();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: tripService),
        ChangeNotifierProvider(create: (_) => SpeedAlertService()),
        ChangeNotifierProvider(create: (_) => SpeedService()),
        ChangeNotifierProvider(create: (_) => RouteService()),
        ChangeNotifierProvider(create: (_) => GpsSpeedService()),
        ChangeNotifierProvider(create: (_) => AutoParametersService()),
        ChangeNotifierProvider(create: (_) => VisibilityService()),
        ChangeNotifierProvider(create: (_) => MotionSensorService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
