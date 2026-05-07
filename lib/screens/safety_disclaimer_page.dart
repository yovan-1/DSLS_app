import 'package:flutter/material.dart';

class SafetyDisclaimerPage extends StatelessWidget {
  const SafetyDisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Safety Disclaimer"), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Icon
            Center(
              child: Icon(
                Icons.shield_outlined,
                size: 80,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 24),

            const Center(
              child: Text(
                "Important Safety Information",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 32),

            const Text(
              "This system is designed to assist drivers by providing intelligent speed recommendations based on real-time conditions.",
              style: TextStyle(fontSize: 16, height: 1.6),
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "⚠️  Important Notice",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    "• This application is intended for guidance purposes only.\n\n"
                    "• The driver is solely responsible for the safe operation of the vehicle at all times.\n\n"
                    "• You must obey all posted speed limits, traffic signs, and road conditions.\n\n"
                    "• The system does not replace attentive driving, good judgment, or legal responsibilities.",
                    style: TextStyle(fontSize: 15.5, height: 1.7),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            const Text(
              "By using this system, you acknowledge that you understand and accept the above terms.",
              style: TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
