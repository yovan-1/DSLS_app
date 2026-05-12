import 'package:flutter/material.dart';
import '../services/trip_service.dart';

class StatsRow extends StatelessWidget {
  final TripService service;

  const StatsRow({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            "Total Trips",
            "${service.totalTrips}",
            Icons.directions_car,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            "Total Distance",
            "${service.totalDistance} km",
            Icons.route,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            "Avg Speed",
            "${service.averageSpeed.round()} km/h",
            Icons.speed,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.blue),
          SizedBox(height: 5),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
