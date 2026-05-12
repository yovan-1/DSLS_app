import 'package:flutter/material.dart';
import '../models/speed_calculator.dart';

class ParameterCards extends StatelessWidget {
  final SpeedParameters params;

  const ParameterCards({super.key, required this.params});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildCard(
            child: Column(
              children: [
                Icon(
                  SpeedCalculator.getWeatherIcon(params.weather),
                  color: Color(0xFF00E676),
                ),
                Text(
                  "Weather",
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                Text(
                  SpeedCalculator.getWeatherLabel(params.weather),
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
                  SpeedCalculator.getLocationIcon(params.location),
                  color: Color(0xFF00E676),
                ),
                Text(
                  "Location",
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                Text(
                  SpeedCalculator.getLocationLabel(params.location),
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
                Icon(Icons.visibility, color: Color(0xFF00E676)),
                Text(
                  "Visibility",
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                Text(
                  SpeedCalculator.getVisibilityLabel(params.visibility),
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
