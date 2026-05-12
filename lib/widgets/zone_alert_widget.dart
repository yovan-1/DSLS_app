import 'package:flutter/material.dart';
import '../services/location_speed_service.dart';

class ZoneAlertWidget extends StatefulWidget {
  final LocationSpeedResult locationResult;

  const ZoneAlertWidget({
    super.key,
    required this.locationResult,
  });

  @override
  State<ZoneAlertWidget> createState() => _ZoneAlertWidgetState();
}

class _ZoneAlertWidgetState extends State<ZoneAlertWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.locationResult.status;
    final isActive = status == LocationSpeedStatus.inZone ||
        status == LocationSpeedStatus.approachingZone;

    if (!isActive) {
      return SizedBox.shrink();
    }

    final isInZone = status == LocationSpeedStatus.inZone;
    final color = isInZone ? Colors.red : Colors.orange;
    final speedLimit = widget.locationResult.speedLimit;
    final zoneName = widget.locationResult.activeZoneName.isNotEmpty
        ? widget.locationResult.activeZoneName
        : widget.locationResult.activeRoadName;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: 0.5 + (_animation.value * 0.5),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            margin: EdgeInsets.only(bottom: 15),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color,
                width: isInZone ? 3 : 2,
              ),
              boxShadow: isInZone
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isInZone ? Icons.warning : Icons.speed,
                      color: color,
                      size: 28,
                    ),
                    SizedBox(width: 8),
                    Text(
                      isInZone ? 'ZONE WARNING' : 'APPROACHING ZONE',
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  zoneName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'MAX $speedLimit km/h',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
