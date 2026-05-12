import 'package:flutter/material.dart';
import '../services/trip_service.dart';

class TrendGraph extends StatelessWidget {
  final List<dynamic> trips;

  const TrendGraph({super.key, required this.trips});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (index) {
          final trip = index < trips.length ? trips[index] : null;
          final height =
              trip != null
                  ? (100 - (trip.overSpeedCount ?? 0) * 10).clamp(20, 100).toDouble()
                  : 20.0;
          final color =
              (trip?.overSpeedCount ?? 0) > 3 ? Colors.red : Colors.green;

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 30,
                height: height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              SizedBox(height: 5),
              Text(
                ["M", "T", "W", "T", "F", "S", "S"][index],
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          );
        }),
      ),
    );
  }
}
