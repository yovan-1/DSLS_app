import 'package:flutter/material.dart';
import '../models/speed_calculator.dart';
import '../models/speed_model/road_conditions.dart';
import '../models/speed_model/solar_position.dart';

class ParameterCards extends StatelessWidget {
  final RoadConditions conditions;

  const ParameterCards({super.key, required this.conditions});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildCard(
            child: Column(
              children: [
                Icon(
                  SpeedCalculator.getWeatherIcon(conditions.weather),
                  color: Color(0xFF00E676),
                ),
                Text(
                  "Weather",
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                Text(
                  SpeedCalculator.getWeatherLabel(conditions.weather),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF00E676),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _buildCard(
            child: Column(
              children: [
                Icon(
                  SpeedCalculator.getLocationIcon(conditions.roadClass),
                  color: Color(0xFF00E676),
                ),
                Text(
                  "Location",
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                Text(
                  SpeedCalculator.getLocationLabel(conditions.roadClass),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF00E676),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _buildCard(
            child: Column(
              children: [
                Icon(Icons.light_mode, color: Color(0xFF00E676)),
                Text(
                  "Light",
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                Text(
                  SolarPosition.label(conditions.daylight),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF00E676),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 5),
        ],
      ),
      child: child,
    );
  }
}
