import 'package:flutter/material.dart';
import '../services/trip_service.dart';

class BehaviorSummary extends StatelessWidget {
  final TripService tripService;

  const BehaviorSummary({super.key, required this.tripService});

  @override
  Widget build(BuildContext context) {
    final safe = tripService.safeDrivingPercent;
    final moderate = tripService.moderateDrivingPercent;
    final risky = tripService.riskyDrivingPercent;

    if (tripService.drivingRecords.isEmpty) {
      return SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Driving Behavior Analysis",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _buildBehaviorCard(
                  "Safe",
                  "$safe%",
                  Colors.green,
                  Icons.check_circle,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _buildBehaviorCard(
                  "Moderate",
                  "$moderate%",
                  Colors.orange,
                  Icons.warning,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _buildBehaviorCard(
                  "Risky",
                  "$risky%",
                  Colors.red,
                  Icons.dangerous,
                ),
              ),
            ],
          ),
          SizedBox(height: 15),
          LinearProgressIndicator(
            value: safe / 100,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Safe", style: TextStyle(fontSize: 10, color: Colors.green)),
              Text(
                "Moderate",
                style: TextStyle(fontSize: 10, color: Colors.orange),
              ),
              Text("Risky", style: TextStyle(fontSize: 10, color: Colors.red)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBehaviorCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
