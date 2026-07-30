import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/alert_service.dart';
import 'how_it_works_page.dart';
import 'safety_disclaimer_page.dart';
import 'developers_page.dart';
import 'contact_us_page.dart';
import 'feedback_page.dart';
import 'cloud_sync_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Dynamic Speed Limit System",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text(
                "Version 1.0",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Alert Settings Section
          _AlertSettingsSection(),

          const SizedBox(height: 12),

          _SettingsCard(
            title: "Cloud Sync",
            subtitle: "Upload trip data to AWS S3",
            icon: Icons.cloud_upload,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CloudSyncScreen()),
            ),
          ),

          const SizedBox(height: 12),

          _SettingsCard(
            title: "How It Works",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HowItWorksPage()),
            ),
          ),

          const SizedBox(height: 12),

          _SettingsCard(
            title: "Safety Disclaimer",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SafetyDisclaimerPage()),
            ),
          ),

          const SizedBox(height: 12),

          _SettingsCard(
            title: "Developers",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DevelopersPage()),
            ),
          ),

          const SizedBox(height: 40),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactUsPage()),
                  ),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text("Contact Us"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FeedbackPage()),
                  ),
                  icon: const Icon(Icons.feedback_outlined),
                  label: const Text("Feedback"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertSettingsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SpeedAlertService>(
      builder: (context, alertService, child) {
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notifications_active, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Alert Settings",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // TTS Status
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    alertService.ttsAvailable ? Icons.check_circle : Icons.error,
                    color: alertService.ttsAvailable ? Colors.green : Colors.red,
                  ),
                  title: const Text("Voice Status"),
                  subtitle: Text(
                    alertService.ttsAvailable
                        ? "Voice alerts ready"
                        : "Voice unavailable - using sounds only",
                  ),
                  trailing: null,
                ),

                const Divider(),

                // Test Voice Button
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.volume_up),
                  title: const Text("Test Voice"),
                  subtitle: const Text("Tap to hear voice announcement"),
                  onTap: () {
                    alertService.testTts();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Testing voice announcement..."),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  trailing: const Icon(Icons.chevron_right),
                ),

                const Divider(),

                // Sound Toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.volume_up),
                  title: const Text("Sound Alerts"),
                  subtitle: const Text("Play sound when speeding"),
                  value: alertService.enableSound,
                  onChanged: (value) => alertService.setEnableSound(value),
                ),

                // Vibration Toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.vibration),
                  title: const Text("Vibration"),
                  subtitle: const Text("Vibrate on alerts"),
                  value: alertService.enableVibration,
                  onChanged: (value) => alertService.setEnableVibration(value),
                ),

                // Zone Alerts Toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.location_on),
                  title: const Text("Zone Alerts"),
                  subtitle: const Text("Alert when approaching zones"),
                  value: alertService.enableZoneAlerts,
                  onChanged: (value) => alertService.setEnableZoneAlerts(value),
                ),

                const Divider(),

                // Speed Thresholds
                _ThresholdSetting(
                  label: "Warning Speed",
                  subtitle: "Alert when over by ${alertService.warningAheadSpeed} km/h",
                  value: alertService.warningAheadSpeed.toDouble(),
                  min: 0,
                  max: 20,
                  onChanged: (value) =>
                      alertService.setWarningAheadSpeed(value.round()),
                ),

                const SizedBox(height: 8),

                _ThresholdSetting(
                  label: "Critical Speed",
                  subtitle: "Alert when over by ${alertService.criticalAheadSpeed} km/h",
                  value: alertService.criticalAheadSpeed.toDouble(),
                  min: 5,
                  max: 30,
                  onChanged: (value) =>
                      alertService.setCriticalAheadSpeed(value.round()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThresholdSetting extends StatelessWidget {
  final String label;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _ThresholdSetting({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "${value.round()} km/h",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).round(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.title,
    this.subtitle,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        leading: icon != null ? Icon(icon, color: Colors.blue) : null,
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        onTap: onTap,
      ),
    );
  }
}