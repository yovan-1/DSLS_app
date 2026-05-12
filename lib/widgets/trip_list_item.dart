import 'package:flutter/material.dart';
import '../models/speed_calculator.dart';
import '../models/trip_data.dart';
import '../services/trip_service.dart';
import 'trip_details_screen.dart';

class TripListItem extends StatelessWidget {
  final TripData trip;
  final TripService service;
  final Function(String) onDelete;

  const TripListItem({
    super.key,
    required this.trip,
    required this.service,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final locationLabel = SpeedCalculator.getLocationLabel(trip.location);
    final riskColor =
        trip.overSpeedCount > 5
            ? Colors.red
            : (trip.overSpeedCount > 2 ? Colors.orange : Colors.green);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TripDetailsScreen(trip: trip)),
      ),
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.directions_car, color: Colors.blue),
                    SizedBox(width: 10),
                    Text(
                      locationLabel,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  _formatDate(trip.startTime),
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTripStat("Duration", trip.formattedDuration),
                _buildTripStat("Max Speed", "${trip.maxSpeed} km/h"),
                _buildTripStat(
                  "Over Speed",
                  "${trip.overSpeedCount}x",
                  color: riskColor,
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Recommended: ${trip.recommendedSpeed} km/h",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Row(
                  children: [
                    Text(
                      "Tap for details",
                      style: TextStyle(fontSize: 10, color: Colors.blue.shade300),
                    ),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _confirmDelete(context),
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.red.shade300,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripStat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Trip"),
        content: Text("Are you sure you want to delete this trip?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              onDelete(trip.id);
              Navigator.pop(context);
            },
            child: Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
