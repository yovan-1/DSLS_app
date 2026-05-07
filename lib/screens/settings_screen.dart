import 'package:flutter/material.dart';
import 'how_it_works_page.dart';
import 'safety_disclaimer_page.dart';
import 'developers_page.dart';
import 'contact_us_page.dart';
import 'feedback_page.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

          const SizedBox(height: 24),

          _SettingsCard(
            title: "How It Works",
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HowItWorksPage()),
                ),
          ),

          const SizedBox(height: 12),

          _SettingsCard(
            title: "Safety Disclaimer",
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SafetyDisclaimerPage(),
                  ),
                ),
          ),

          const SizedBox(height: 12),

          _SettingsCard(
            title: "Developers",
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DevelopersPage()),
                ),
          ),

          const SizedBox(height: 40),

          // Updated Bottom Buttons - Now Navigate to Pages
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ContactUsPage(),
                        ),
                      ),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text("Contact Us"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FeedbackPage()),
                      ),
                  icon: const Icon(Icons.feedback_outlined),
                  label: const Text("Feedback"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Reusable Card (unchanged)
class _SettingsCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _SettingsCard({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        onTap: onTap,
      ),
    );
  }
}
