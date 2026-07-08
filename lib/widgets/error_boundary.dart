import 'package:flutter/material.dart';

String describeAppError(Object? error) {
  final s = error.toString();
  if (s.contains('SocketException') || s.contains('Network is unreachable')) {
    return 'Network connection error. Please check your internet connection.';
  }
  if (s.contains('Location')) {
    return 'Unable to get location. Please enable GPS permissions.';
  }
  if (s.contains('Camera')) {
    return 'Camera access error. Please check camera permissions.';
  }
  if (s.contains('Permission')) {
    return 'Permission denied. Please grant required permissions in settings.';
  }
  return 'An unexpected error occurred. Please try again.';
}

class AppErrorScreen extends StatelessWidget {
  final Object? error;
  final VoidCallback onRestart;

  const AppErrorScreen({super.key, required this.error, required this.onRestart});

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Something went wrong',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  describeAppError(error),
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restart App'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
