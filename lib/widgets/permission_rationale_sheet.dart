import 'package:flutter/material.dart';

import '../services/permission_flow.dart';

/// In-context explanation shown immediately before a system permission prompt.
///
/// The app used to fire a bare camera request from the Start button with no
/// explanation. A cold prompt is the most common reason permissions get denied,
/// and a denial here costs the user monitoring that stops the moment their
/// screen locks.
class PermissionRationaleSheet extends StatelessWidget {
  final PermissionStep step;

  const PermissionRationaleSheet({super.key, required this.step});

  /// Returns true when the user is willing to see the system prompt.
  static Future<bool> show(BuildContext context, PermissionStep step) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: !step.isRequired,
      builder: (_) => PermissionRationaleSheet(step: step),
    );
    return accepted ?? false;
  }

  IconData get _icon => switch (step) {
        PermissionStep.fineLocation => Icons.my_location,
        PermissionStep.notifications => Icons.notifications_active_outlined,
        PermissionStep.backgroundLocation => Icons.lock_clock,
        PermissionStep.camera => Icons.light_mode_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon, size: 32, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    step.title,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(step.rationale, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'If you decline: ${step.consequenceIfDenied}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
            if (!step.isRequired)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
          ],
        ),
      ),
    );
  }
}
