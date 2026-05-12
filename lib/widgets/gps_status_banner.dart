import 'package:flutter/material.dart';
import '../services/gps_speed_service.dart';

class GpsStatusBanner extends StatelessWidget {
  final GpsStatus gpsStatus;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const GpsStatusBanner({
    super.key,
    required this.gpsStatus,
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (gpsStatus != GpsStatus.lost && errorMessage == null) {
      return SizedBox.shrink();
    }

    if (gpsStatus == GpsStatus.lost) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(12),
        margin: EdgeInsets.only(bottom: 15),
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange),
        ),
        child: Row(
          children: [
            Icon(Icons.gps_off, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "GPS signal lost - using last known position",
                style: TextStyle(color: Colors.orange.shade800),
              ),
            ),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(12),
        margin: EdgeInsets.only(bottom: 15),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red),
        ),
        child: Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                errorMessage!,
                style: TextStyle(color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text("Retry"),
            ),
          ],
        ),
      );
    }

    return SizedBox.shrink();
  }
}
