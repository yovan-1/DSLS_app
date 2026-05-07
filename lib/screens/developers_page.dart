import 'package:flutter/material.dart';

class DevelopersPage extends StatelessWidget {
  const DevelopersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Developers"), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Column(
                children: [
                  Icon(Icons.code_rounded, size: 80, color: Colors.blue),
                  SizedBox(height: 16),
                  Text(
                    "Dynamic Speed Limit System",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Version 1.0",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            const Text(
              "Developed with ❤️ for safer roads",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 28),

            // Developer / Team Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Development Team",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20),
                    _DeveloperTile(
                      name: "Ikayo Emmanuel ",
                      role: "Lead Developer & Designer",
                    ),
                    Divider(height: 30),
                    _DeveloperTile(
                      name: "Ainomujuni Yovan",
                      role: "Backend & AI Engineer",
                    ),
                    Divider(height: 30),
                    _DeveloperTile(
                      name: "Elizabeth Hanania",
                      role: "UI/UX Designer",
                    ),
                    Divider(height: 30),
                    _DeveloperTile(
                      name: "David Okello",
                      role: "Data Scientist",
                    ),
                    Divider(height: 30),
                    _DeveloperTile(
                      name: "Muwonge Stuart",
                      role: "Database Developer",
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // About Section
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "About This Project",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      "This application was built to promote road safety by providing intelligent, real-time speed recommendations using GPS, weather data, and risk analysis.",
                      style: TextStyle(fontSize: 15.5, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            const Center(
              child: Text(
                "© 2026 Dynamic Speed Systems\nAll Rights Reserved",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Reusable Developer Tile
class _DeveloperTile extends StatelessWidget {
  final String name;
  final String role;

  const _DeveloperTile({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 24,
          backgroundColor: Colors.blue,
          child: Icon(Icons.person, color: Colors.white),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                role,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
