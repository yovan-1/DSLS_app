import 'package:flutter/material.dart' hide DayPeriod;
import 'package:provider/provider.dart';
import '../services/driving_session_coordinator.dart';
import '../services/gps_speed_service.dart';
import '../models/speed_model/road_conditions.dart' show LimitSource;
import '../services/location_speed_service.dart';
import '../services/permission_flow.dart';
import '../services/visibility_service.dart';
import '../widgets/permission_rationale_sheet.dart';
import '../widgets/speedometer_widget.dart';
import '../widgets/zone_alert_widget.dart';
import '../widgets/parameter_cards.dart';
import '../widgets/over_speed_flash.dart';
import '../widgets/gps_status_banner.dart';
import '../widgets/condition_status_card.dart';
import '../utils/speed_colors.dart';

/// Renders the current drive. Owns no driving logic of its own — everything is
/// read from [DrivingSessionCoordinator], which keeps running whether or not
/// this widget is on screen.
class SpeedScreen extends StatelessWidget {
  const SpeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<DrivingSessionCoordinator>();
    final state = coordinator.state;

    final speedColor = SpeedColors.forSpeed(
      currentSpeed: state.speedKph,
      recommendedSpeed: state.recommendedSpeedKph,
    );
    final warnings =
        state.recommendation.advisories.map((a) => a.message).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00E676),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          "Speed Limit",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                GpsStatusBanner(
                  gpsStatus: state.gpsStatus,
                  errorMessage: state.errorMessage,
                  onRetry: () => context.read<GpsSpeedService>().checkPermission(),
                ),
                SpeedometerWidget(
                  currentSpeed: state.speedKph,
                  recommendedSpeed: state.recommendedSpeedKph,
                  color: speedColor,
                  isTracking: state.isActive,
                  animationDurationMs:
                      context.read<GpsSpeedService>().animationDurationMs,
                ),
                const SizedBox(height: 20),
                ZoneAlertWidget(locationResult: state.locationResult),
                _buildUnmappedRoadNotice(state),
                const SizedBox(height: 20),
                _buildOverSpeedAlert(state),
                _buildWarnings(warnings),
                _buildStartStopButton(context, coordinator, state),
                const SizedBox(height: 20),
                ParameterCards(conditions: state.conditions),
                const SizedBox(height: 10),
                ConditionStatusCard(
                  weatherStatus: state.weatherStatus,
                  visibilityService: context.watch<VisibilityService>(),
                  baseSpeedLimit: state.conditions.speedLimitKph,
                  gpsService: context.watch<GpsSpeedService>(),
                ),
              ],
            ),
          ),
          if (state.isOverSpeed)
            Positioned.fill(
              child: OverSpeedFlash(diff: state.overSpeedDiff),
            ),
        ],
      ),
    );
  }

  /// Says how much the app actually knows about the current limit.
  ///
  /// Three cases, and they are genuinely different. Off any mapped road there
  /// is no limit at all, only a flat fallback. On a mapped road the limit is
  /// usually derived from the road's class rather than a posted sign — just
  /// 1.6% of ways in the shipped extract carry a `maxspeed` tag — and saying so
  /// is the difference between an estimate and a claim. Only a posted limit or
  /// a curated zone is presented without a caveat.
  Widget _buildUnmappedRoadNotice(DrivingSessionState state) {
    if (!state.isActive) return const SizedBox.shrink();

    final location = state.locationResult;
    final String message;
    final IconData icon;

    if (location.status == LocationSpeedStatus.none) {
      icon = Icons.help_outline;
      message = "No mapped speed limit here — showing a conservative default. "
          "Follow the posted signs.";
    } else if (location.limitSource == LimitSource.inferred) {
      icon = Icons.info_outline;
      message = "Limit estimated from the road type, not a posted sign. "
          "Follow the signs.";
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade400),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverSpeedAlert(DrivingSessionState state) {
    if (state.speedKph <= state.recommendedSpeedKph) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Over speed by ${state.overSpeedDiff} km/h",
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarnings(List<String> warnings) {
    if (warnings.isEmpty) return const SizedBox.shrink();

    return Column(
      children: warnings
          .map((w) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(w, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildStartStopButton(
    BuildContext context,
    DrivingSessionCoordinator coordinator,
    DrivingSessionState state,
  ) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: state.isActive ? Colors.red : Colors.green,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      onPressed: () async {
        if (state.isActive) {
          await coordinator.stop();
          return;
        }

        final messenger = ScaffoldMessenger.of(context);

        // Ask before starting, one permission at a time, each behind its own
        // rationale. Only fine location blocks — the rest degrade.
        final permissions = await const PermissionFlow().requestForDrive(
          showRationale: (step) => PermissionRationaleSheet.show(context, step),
        );

        if (!permissions.canDrive) {
          messenger.showSnackBar(const SnackBar(
            content: Text(
              'Location access is required to monitor your driving.',
            ),
          ));
          return;
        }

        final started = await coordinator.start();
        if (!started) {
          final error = coordinator.state.errorMessage;
          if (error != null) {
            messenger.showSnackBar(SnackBar(content: Text(error)));
          }
          return;
        }

        // Say plainly what the drive will and will not do, rather than letting
        // the user discover at the roadside that it stopped when the screen
        // locked.
        if (!permissions.survivesScreenLock) {
          messenger.showSnackBar(const SnackBar(
            content: Text(
              'Monitoring may stop when your screen locks — grant background '
              'location and notifications to keep it running.',
            ),
            duration: Duration(seconds: 6),
          ));
        }
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            state.isActive ? Icons.stop_circle : Icons.directions_car,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            state.isActive ? "Stop Driving" : "Start Driving",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
