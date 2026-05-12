import 'package:flutter/material.dart';
import '../services/gps_speed_service.dart';
import '../services/visibility_service.dart';

class ConditionStatusCard extends StatelessWidget {
  final String weatherStatus;
  final VisibilityService visibilityService;
  final int baseSpeedLimit;
  final GpsSpeedService gpsService;

  const ConditionStatusCard({
    super.key,
    required this.weatherStatus,
    required this.visibilityService,
    required this.baseSpeedLimit,
    required this.gpsService,
  });

  @override
  Widget build(BuildContext context) {
    final visibilitySource = visibilityService.permissionDenied
        ? 'Visibility: camera denied, using time/weather estimate'
        : (visibilityService.isInitialized
            ? 'Visibility: camera + time/weather estimate'
            : 'Visibility: time/weather estimate until driving starts');

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            weatherStatus,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          SizedBox(height: 4),
          Text(
            visibilitySource,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          SizedBox(height: 4),
          Text(
            'Base limit in use: $baseSpeedLimit km/h',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (gpsService.isTracking) ...[
            SizedBox(height: 4),
            Text(
              'Fusion: ${_getFusionStatusText(gpsService.fusionStatus)} | GPS: ${gpsService.smoothedSpeed} km/h',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getFusionStatusText(FusionStatus status) {
    switch (status) {
      case FusionStatus.gpsOnly:
        return 'GPS Only';
      case FusionStatus.accelFusion:
        return 'GPS+Accel';
      case FusionStatus.fullFusion:
        return 'Full Fusion';
    }
  }
}
