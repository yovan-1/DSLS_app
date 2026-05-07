import 'package:flutter/material.dart' hide DayPeriod;
import '../models/speed_calculator.dart';
import '../models/trip_data.dart';

class TripDetailsScreen extends StatelessWidget {
  final TripData trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("Trip Details", style: TextStyle(color: Colors.black)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderCard(),
            SizedBox(height: 20),
            _buildSpeedStats(),
            SizedBox(height: 20),
            _buildTripInfo(),
            SizedBox(height: 20),
            if (trip.alerts.isNotEmpty) ...[
              _buildAlertsSection(),
              SizedBox(height: 20),
            ],
            _buildRiskAssessment(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final riskColor = trip.overSpeedCount > 5
        ? Colors.red
        : (trip.overSpeedCount > 2 ? Colors.orange : Colors.green);

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue, Colors.blue.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getLocationIcon(trip.location),
              color: Colors.white,
              size: 40,
            ),
          ),
          SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SpeedCalculator.getLocationLabel(trip.location),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  _formatFullDate(trip.startTime),
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: riskColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    trip.overSpeedCount == 0
                        ? "No Overspeeding"
                        : "${trip.overSpeedCount}x Overspeeding",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedStats() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Speed Statistics",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSpeedCard(
                  "Base Limit",
                  "${trip.baseSpeedLimit}",
                  "km/h",
                  Icons.speed,
                  Colors.grey,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _buildSpeedCard(
                  "Recommended",
                  "${trip.recommendedSpeed}",
                  "km/h",
                  Icons.thumb_up,
                  Colors.green,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildSpeedCard(
                  "Max Speed",
                  "${trip.maxSpeed}",
                  "km/h",
                  Icons.trending_up,
                  Colors.orange,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _buildSpeedCard(
                  "Avg Speed",
                  "${trip.avgSpeed}",
                  "km/h",
                  Icons.show_chart,
                  Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedCard(String label, String value, String unit, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            unit,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTripInfo() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Trip Information",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 15),
          _buildInfoRow("Start Time", _formatFullDate(trip.startTime)),
          _buildInfoRow(
            "End Time",
            trip.endTime != null ? _formatFullDate(trip.endTime!) : "In Progress",
          ),
          _buildInfoRow("Duration", trip.formattedDuration),
          _buildInfoRow("Trip ID", trip.id),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildAlertsSection() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 10),
              Text(
                "Speed Alerts (${trip.alerts.length})",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 15),
          ...trip.alerts.take(10).map((alert) => _buildAlertItem(alert)),
          if (trip.alerts.length > 10)
            Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                "+ ${trip.alerts.length - 10} more alerts",
                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlertItem(SpeedAlert alert) {
    final speedDiff = alert.speed - alert.recommendedSpeed;
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.speed, color: Colors.red, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Overspeed Alert",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  "Speed: ${alert.speed} km/h (limit: ${alert.recommendedSpeed})",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Text(
            "+$speedDiff",
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskAssessment() {
    String riskLevel;
    Color riskColor;
    String advice;
    IconData riskIcon;

    if (trip.overSpeedCount == 0) {
      riskLevel = "Excellent";
      riskColor = Colors.green;
      advice = "Great driving! You maintained safe speeds throughout the trip.";
      riskIcon = Icons.star;
    } else if (trip.overSpeedCount <= 2) {
      riskLevel = "Good";
      riskColor = Colors.lightGreen;
      advice = "Good driving overall. Minor speed adjustments were needed.";
      riskIcon = Icons.thumb_up;
    } else if (trip.overSpeedCount <= 5) {
      riskLevel = "Moderate";
      riskColor = Colors.orange;
      advice = "Consider reducing speed to improve safety.";
      riskIcon = Icons.warning;
    } else {
      riskLevel = "Needs Improvement";
      riskColor = Colors.red;
      advice = "Multiple overspeeding incidents detected. Please drive more carefully.";
      riskIcon = Icons.dangerous;
    }

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: riskColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: riskColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(riskIcon, color: riskColor, size: 40),
          SizedBox(height: 10),
          Text(
            riskLevel,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: riskColor,
            ),
          ),
          SizedBox(height: 10),
          Text(
            advice,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  IconData _getLocationIcon(LocationType location) {
    switch (location) {
      case LocationType.highway:
        return Icons.speed;
      case LocationType.urban:
        return Icons.location_city;
      case LocationType.suburban:
        return Icons.holiday_village;
      case LocationType.residential:
        return Icons.home;
      case LocationType.schoolZone:
        return Icons.school;
      case LocationType.constructionZone:
        return Icons.construction;
      default:
        return Icons.directions_car;
    }
  }

  String _formatFullDate(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
