import 'package:flutter/material.dart';
import '../models/trip_data.dart';

class ScoreCard extends StatelessWidget {
  final DrivingScore score;

  const ScoreCard({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    Color scoreColor;
    if (score.overall >= 80) {
      scoreColor = Colors.green;
    } else if (score.overall >= 60) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scoreColor, scoreColor.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                score.grade,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
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
                  "Driving Score",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  score.description,
                  style: TextStyle(color: Colors.white70),
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    _buildMiniStat("Speed", "${score.speedCompliance}%"),
                    SizedBox(width: 15),
                    _buildMiniStat("Smooth", "${score.smoothness}%"),
                    SizedBox(width: 15),
                    _buildMiniStat("Focus", "${score.attention}%"),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }
}
