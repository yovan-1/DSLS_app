import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show navigatorKey;
import '../services/settings_service.dart';
import 'dashboard.dart';
import 'safety_disclaimer_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(seconds: 2), _advance);
  }

  Future<void> _advance() async {
    if (!mounted) return;
    final settings = context.read<SettingsService>();
    final isFirstLaunch = await settings.isFirstLaunch();
    if (!mounted) return;

    if (!isFirstLaunch) {
      _goToDashboard();
      return;
    }

    // The app can start issuing over-speed alerts within seconds of install, so
    // the disclaimer has to be accepted before the driver ever reaches it.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SafetyDisclaimerPage(
          requireAcceptance: true,
          onAccepted: () async {
            await settings.markFirstLaunchComplete();
            _goToDashboard();
          },
        ),
      ),
    );
  }

  /// Goes through the root navigator rather than this State's context: by the
  /// time the disclaimer's Accept button fires, this State has already been
  /// disposed by the pushReplacement above, so a `mounted` guard here would
  /// silently swallow the navigation and leave the button dead.
  void _goToDashboard() {
    navigatorKey.currentState?.pushReplacement(
      MaterialPageRoute(builder: (_) => const Dashboard()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.speed, size: 50),
              ),
              const SizedBox(height: 20),
              const Text(
                'DYNAMIC SPEED\nLIMIT SYSTEM',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Container(width: 60, height: 3, color: Colors.blue),
              const SizedBox(height: 15),
              const Text('Drive Smart. Drive Safe.'),
              const SizedBox(height: 30),
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              const Text('Loading...'),
            ],
          ),
        ),
      ),
    );
  }
}
