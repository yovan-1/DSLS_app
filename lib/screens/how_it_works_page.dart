import 'package:flutter/material.dart';

class HowItWorksPage extends StatelessWidget {
  const HowItWorksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("How It Works"), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Dynamic Speed Limit System",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Version 1.0",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),

            const Text(
              "This system intelligently adjusts speed recommendations in real-time to enhance safety and driving comfort.",
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 32),

            // Feature Cards
            _FeatureCard(
              icon: Icons.location_on,
              title: "GPS Data Collection",
              description:
                  "Continuously monitors your vehicle's location and speed using high-accuracy GPS.",
            ),
            const SizedBox(height: 16),

            _FeatureCard(
              icon: Icons.cloud,
              title: "Weather Integration",
              description:
                  "Fetches real-time weather conditions to adjust speed limits based on rain, fog, or poor visibility.",
            ),
            const SizedBox(height: 16),

            _FeatureCard(
              icon: Icons.analytics,
              title: "Risk Analysis",
              description:
                  "Analyzes road conditions, traffic patterns, and driving behavior to calculate optimal safe speeds.",
            ),
            const SizedBox(height: 16),

            _FeatureCard(
              icon: Icons.speed,
              title: "Smart Speed Recommendation",
              description:
                  "Provides intelligent speed suggestions tailored to current driving conditions.",
            ),
            const SizedBox(height: 16),

            _FeatureCard(
              icon: Icons.notifications_active,
              title: "Instant Alerts",
              description:
                  "Sends timely visual and audio alerts when you exceed the recommended safe speed.",
            ),
          ],
        ),
      ),
    );
  }
}

// Reusable Beautiful Feature Card
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.blue.shade50,
              child: Icon(icon, color: Colors.blue.shade700, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
