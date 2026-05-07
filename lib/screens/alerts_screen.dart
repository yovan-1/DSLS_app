import 'package:flutter/material.dart' hide DayPeriod;
import 'package:provider/provider.dart';
import '../models/trip_data.dart';
import '../services/alert_service.dart';
import '../services/trip_service.dart';

class AlertsScreen extends StatelessWidget {
  final Function(int)? onBack;

  const AlertsScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Consumer2<SpeedAlertService, TripService>(
      builder: (context, alertService, tripService, child) {
        final score = tripService.drivingScore;
        final currentTrip = tripService.currentTrip;
        final alerts = currentTrip?.alerts ?? [];

        return Scaffold(
          backgroundColor: Colors.grey.shade100,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 1,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => onBack?.call(0),
            ),
            title: Text("Risk Analysis", style: TextStyle(color: Colors.black)),
            centerTitle: true,
            actions: [],
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRiskOverview(score, alertService),
                SizedBox(height: 20),
                Text(
                  "Active Alerts",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                if (alerts.isEmpty)
                  _buildNoAlertsCard()
                else
                  ...alerts.map((alert) => _buildAlertCard(alert)),
                SizedBox(height: 20),
                Text(
                  "Risk Breakdown",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                _buildRiskBreakdown(score),
                SizedBox(height: 20),
                Text(
                  "Alert Settings",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                _buildAlertSettingsCard(context, alertService),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRiskOverview(DrivingScore score, SpeedAlertService service) {
    final riskLevel = _getRiskLevel(score.overall);
    final color = _getScoreColor(score.overall);

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                "${score.overall}",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
          SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Overall Risk",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  riskLevel,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  score.description,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoAlertsCard() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.green),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 40),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "No Active Alerts",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Text(
                  "You're driving safely within the recommended speed",
                  style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(SpeedAlert alert) {
    final color =
        alert.type == AlertType.overSpeed ? Colors.red : Colors.orange;

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(
            alert.type == AlertType.overSpeed ? Icons.speed : Icons.warning,
            color: color,
          ),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Speed: ${alert.speed} km/h",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "Recommended: ${alert.recommendedSpeed} km/h",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  _formatTime(alert.time),
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "+1",
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskBreakdown(DrivingScore score) {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          _buildRiskRow("Speed Compliance", score.speedCompliance),
          SizedBox(height: 10),
          _buildRiskRow("Driving Smoothness", score.smoothness),
          SizedBox(height: 10),
          _buildRiskRow("Attention & Focus", score.attention),
        ],
      ),
    );
  }

  Widget _buildRiskRow(String label, int value) {
    final color = _getScoreColor(value);
    return Row(
      children: [
        Expanded(flex: 2, child: Text(label)),
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: value / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 10,
            ),
          ),
        ),
        SizedBox(width: 10),
        Text("$value%", style: TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildAlertSettingsCard(
    BuildContext context,
    SpeedAlertService service,
  ) {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          _buildSettingRow(
            "Sound Alerts",
            service.enableSound,
            (v) => service.setEnableSound(v),
          ),
          _buildSettingRow(
            "Vibration",
            service.enableVibration,
            (v) => service.setEnableVibration(v),
          ),
          _buildSettingRow(
            "Voice Alerts",
            service.enableVoice,
            (v) => service.setEnableVoice(v),
          ),
          _buildSettingRow(
            "Notifications",
            service.enableNotifications,
            (v) => service.setEnableNotifications(v),
          ),
          Divider(),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Alerts automatically when speeding. Voice uses the phone media volume and Android text-to-speech engine.",
                    style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(String label, bool value, Function(bool) onChanged) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [Text(label), Switch(value: value, onChanged: onChanged)],
      ),
    );
  }

  String _getRiskLevel(int score) {
    if (score >= 80) return "LOW RISK";
    if (score >= 60) return "MEDIUM RISK";
    if (score >= 40) return "HIGH RISK";
    return "VERY HIGH RISK";
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  String _formatTime(DateTime dt) {
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";
  }
}
