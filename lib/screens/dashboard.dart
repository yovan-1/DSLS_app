import 'package:flutter/material.dart' hide DayPeriod;
import '../widgets/bottom_nav.dart';
import 'speed_screen.dart';
import 'alerts_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int currentIndex = 0;
  void changeTab(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const SpeedScreen(),
      AlertsScreen(onBack: changeTab),
      HistoryScreen(onBack: changeTab),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(child: screens[currentIndex]),
      bottomNavigationBar: BottomNav(
        currentIndex: currentIndex,
        onTap: changeTab,
      ),
    );
  }
}
