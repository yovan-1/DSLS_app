import 'package:flutter/material.dart' hide DayPeriod;
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'dart:async';
import '../models/speed_calculator.dart';
import '../services/gps_speed_service.dart';
import '../services/auto_parameters_service.dart';
import '../services/visibility_service.dart';
import '../services/trip_service.dart';
import '../services/speed_service.dart';
import '../services/location_speed_service.dart';
import '../services/alert_service.dart';
import '../services/weather_service.dart';
import '../services/motion_sensor_service.dart';

class SpeedScreen extends StatefulWidget {
  const SpeedScreen({super.key});

  @override
  State<SpeedScreen> createState() => _SpeedScreenState();
}

class _SpeedScreenState extends State<SpeedScreen> {
  Timer? _recordTimer;
  final WeatherService _weatherService = WttrInWeatherService();
  DateTime? _lastWeatherFetch;
  bool _weatherFetchInProgress = false;
  String _weatherStatus = 'Weather will update after GPS starts';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final autoParams = context.read<AutoParametersService>();
      final gpsService = context.read<GpsSpeedService>();
      final speedService = context.read<SpeedService>();

      autoParams.updateTimeOfDay();
      gpsService.setCalculationParams(_effectiveParams(autoParams, speedService));
    });
  }

  void _startRecording(
    GpsSpeedService gpsService,
    AutoParametersService autoParams,
    int recommendedSpeed,
    TripService tripService,
    SpeedService speedService,
    SpeedAlertService alertService,
    VisibilityService visibilityService,
    MotionSensorService motionService,
  ) {
    tripService.startTrip(_effectiveParams(autoParams, speedService));
    visibilityService.initialize().then((_) {
      if (!mounted || !visibilityService.isInitialized) return;
      autoParams.updateVisibility(visibilityService.visibilityLevel);
      speedService.updateVisibility(visibilityService.visibilityLevel);
      gpsService.setCalculationParams(_effectiveParams(autoParams, speedService));
    });
    motionService.initialize().then((_) {
      if (!mounted || !motionService.isInitialized) return;
      if (kDebugMode) {
        debugPrint('[SpeedScreen] Motion sensors initialized');
      }
    });
    alertService.resetAlertState();
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!gpsService.isTracking) {
        _stopRecording(tripService);
        return;
      }

      final risk = gpsService.cachedRiskData;
      final speed = gpsService.fusedSpeed > 0 ? gpsService.fusedSpeed : gpsService.smoothedSpeed;
      final recSpeed = risk?.recommendedSpeed ?? recommendedSpeed;
      final riskLevel = risk?.riskLevel ?? 'LOW';

      if (motionService.isInitialized) {
        gpsService.updateFromAccelerometer(motionService.speedEstimateMps);
      }

      final lastPos = gpsService.lastPosition;
      if (lastPos != null) {
        speedService.updatePosition(lastPos.latitude, lastPos.longitude);
        autoParams.updateLocationType(lastPos);
        _refreshWeatherIfNeeded(
          autoParams,
          speedService,
          visibilityService,
          lastPos.latitude,
          lastPos.longitude,
        );
        gpsService.setCalculationParams(_effectiveParams(autoParams, speedService));
      }

      if (speed > recSpeed) {
        alertService.triggerAlert(speed, recSpeed);
      }

      tripService.addRecord(
        speed: speed,
        recommendedSpeed: recSpeed,
        riskLevel: riskLevel,
      );
    });
    debugPrint('[SpeedScreen] Recording started');
  }


  SpeedParameters _effectiveParams(
    AutoParametersService autoParams,
    SpeedService speedService,
  ) {
    final base = autoParams.currentParams;
    final locationResult = speedService.locationResult;

    if (locationResult.status != LocationSpeedStatus.none) {
      return SpeedParameters(
        weather: base.weather,
        timeOfDay: base.timeOfDay,
        location: locationResult.locationType,
        visibility: base.visibility,
        baseSpeedLimit: locationResult.speedLimit,
      );
    }

    return base;
  }

  Future<void> _refreshWeatherIfNeeded(
    AutoParametersService autoParams,
    SpeedService speedService,
    VisibilityService visibilityService,
    double latitude,
    double longitude, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final recentlyFetched = _lastWeatherFetch != null &&
        now.difference(_lastWeatherFetch!) < const Duration(minutes: 30);

    if (_weatherFetchInProgress || (!force && recentlyFetched)) return;

    _weatherFetchInProgress = true;
    if (mounted) {
      setState(() {
        _weatherStatus = 'Updating weather...';
      });
    }

    try {
      final weather = await _weatherService.getWeather(latitude, longitude);
      if (!mounted) return;

      autoParams.updateWeather(weather.condition);
      speedService.updateWeather(weather.condition);
      visibilityService.updateVisibilityFromWeather(weather.condition);
      _lastWeatherFetch = DateTime.now();

      setState(() {
        _weatherStatus =
            '${SpeedCalculator.getWeatherLabel(weather.condition)} • ${weather.temperature.toStringAsFixed(0)}°C';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weatherStatus = 'Weather unavailable, using safe defaults';
      });
    } finally {
      _weatherFetchInProgress = false;
    }
  }

  void _stopRecording(TripService tripService) {
    _recordTimer?.cancel();
    _recordTimer = null;
    tripService.endTrip();
    debugPrint('[SpeedScreen] Recording stopped');
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gpsService = context.watch<GpsSpeedService>();
    final autoParams = context.watch<AutoParametersService>();
    final visibilityService = context.watch<VisibilityService>();
    final tripService = context.watch<TripService>();
    final speedService = context.watch<SpeedService>();
    final motionService = context.watch<MotionSensorService>();

    if (visibilityService.isInitialized &&
        autoParams.visibility != visibilityService.visibilityLevel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AutoParametersService>().updateVisibility(
              visibilityService.visibilityLevel,
            );
      });
    }

    final isMonitoring = gpsService.isTracking;
    final currentSpeed = gpsService.fusedSpeed > 0 ? gpsService.fusedSpeed : gpsService.smoothedSpeed;
    final errorMessage = gpsService.errorMessage;
    final gpsStatus = gpsService.gpsStatus;

    final params = _effectiveParams(autoParams, speedService);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      gpsService.setCalculationParams(params);
    });

    final cachedRisk = gpsService.cachedRiskData;
    final recommendedSpeed =
        cachedRisk?.recommendedSpeed ??
        SpeedCalculator.calculate(params).recommendedSpeed;
    final speedColor =
        cachedRisk?.speedColor ??
        _getSpeedColor(currentSpeed, recommendedSpeed);
    final warnings =
        cachedRisk?.warnings ?? SpeedCalculator.calculate(params).warnings;
    final isOverSpeeding = isMonitoring && currentSpeed > recommendedSpeed;
    final overSpeedDiff = currentSpeed - recommendedSpeed;

    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: Color(0xFF00E676),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          "Speed Limit",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
            if (gpsStatus == GpsStatus.lost)
              Container(
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
              ),
            if (errorMessage != null)
              Container(
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
                        errorMessage,
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    TextButton(
                      onPressed: () => gpsService.checkPermission(),
                      child: Text("Retry"),
                    ),
                  ],
                ),
              ),
            SpeedometerWidget(
              currentSpeed: currentSpeed,
              recommendedSpeed: recommendedSpeed,
              color: speedColor,
              isTracking: isMonitoring,
              animationDurationMs: gpsService.animationDurationMs,
            ),
            SizedBox(height: 20),
            ZoneAlertWidget(
              locationResult: speedService.locationResult,
            ),
            SizedBox(height: 20),
            if (currentSpeed > recommendedSpeed)
              Container(
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
                    Icon(Icons.warning, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Over speed by ${currentSpeed - recommendedSpeed} km/h",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (warnings.isNotEmpty) ...[
              ...warnings.map(
                (w) => Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(child: Text(w, style: TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 15),
            ],
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isMonitoring ? Colors.red : Colors.green,
                minimumSize: Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: () async {
                if (isMonitoring) {
                  await gpsService.stopTracking();
                  _stopRecording(tripService);
                } else {
                  await gpsService.startTracking();
                  if (!context.mounted) return;
                  if (!gpsService.isTracking) {
                    if (gpsService.errorMessage != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(gpsService.errorMessage!)),
                      );
                    }
                    return;
                  }
                  final speedService = context.read<SpeedService>();
                  final alertService = context.read<SpeedAlertService>();
                  final motionService = context.read<MotionSensorService>();
                  _startRecording(
                    gpsService,
                    autoParams,
                    recommendedSpeed,
                    tripService,
                    speedService,
                    alertService,
                    visibilityService,
                    motionService,
                  );
                }
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isMonitoring ? Icons.stop_circle : Icons.directions_car,
                    color: Colors.white,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Text(
                    isMonitoring ? "Stop Driving" : "Start Driving",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _card(
                    child: Column(
                      children: [
                        Icon(
                          SpeedCalculator.getWeatherIcon(autoParams.weather),
                          color: Color(0xFF00E676),
                        ),
                        Text(
                          "Weather",
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                        Text(
                          SpeedCalculator.getWeatherLabel(autoParams.weather),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF00E676),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _card(
                    child: Column(
                      children: [
                        Icon(
                          SpeedCalculator.getLocationIcon(params.location),
                          color: Color(0xFF00E676),
                        ),
                        Text(
                          "Location",
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                        Text(
                          SpeedCalculator.getLocationLabel(params.location),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF00E676),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _card(
                    child: Column(
                      children: [
                        Icon(Icons.visibility, color: Color(0xFF00E676)),
                        Text(
                          "Visibility",
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                        Text(
                          SpeedCalculator.getVisibilityLabel(
                            params.visibility,
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF00E676),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            _conditionStatusCard(
              weatherStatus: _weatherStatus,
              visibilityService: visibilityService,
              baseSpeedLimit: params.baseSpeedLimit,
              gpsService: gpsService,
            ),
          ],
        ),
      ),
      if (isOverSpeeding)
        Positioned.fill(
          child: _OverSpeedScreenFlash(diff: overSpeedDiff),
        ),
        ],
      ),
    );
  }

  Color _getSpeedColor(int currentSpeed, int recommendedSpeed) {
    if (currentSpeed == 0) return Colors.grey;
    final diff = currentSpeed - recommendedSpeed;
    if (diff <= 0) return Colors.green;
    if (diff <= 10) return Colors.yellow;
    return Colors.red;
  }


  Widget _conditionStatusCard({
    required String weatherStatus,
    required VisibilityService visibilityService,
    required int baseSpeedLimit,
    required GpsSpeedService gpsService,
  }) {
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

  Widget _card({required Widget child}) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 5),
        ],
      ),
      child: child,
    );
  }
}

class _OverSpeedScreenFlash extends StatefulWidget {
  final int diff;

  const _OverSpeedScreenFlash({required this.diff});

  @override
  State<_OverSpeedScreenFlash> createState() => _OverSpeedScreenFlashState();
}

class _OverSpeedScreenFlashState extends State<_OverSpeedScreenFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final opacity = 0.10 + (_controller.value * 0.18);
          return Container(
            color: Colors.red.withValues(alpha: opacity),
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 24, left: 16, right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'SLOW DOWN • +${widget.diff} km/h',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class SpeedometerWidget extends StatefulWidget {
  final int currentSpeed;
  final int recommendedSpeed;
  final Color color;
  final bool isTracking;
  final int animationDurationMs;

  const SpeedometerWidget({
    super.key,
    required this.currentSpeed,
    required this.recommendedSpeed,
    required this.color,
    required this.isTracking,
    this.animationDurationMs = 30,
  });

  @override
  State<SpeedometerWidget> createState() => _SpeedometerWidgetState();
}

class _SpeedometerWidgetState extends State<SpeedometerWidget> {
  int _animatedSpeed = 0;

  @override
  void didUpdateWidget(SpeedometerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSpeed != widget.currentSpeed) {
      setState(() {
        _animatedSpeed = widget.currentSpeed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: _animatedSpeed, end: widget.currentSpeed),
      duration: Duration(milliseconds: widget.animationDurationMs),
      curve: Curves.easeOut,
      builder: (context, animatedSpeed, child) {
        return SizedBox(
          width: 280,
          height: 280,
          child: CustomPaint(
            painter: SpeedometerPainter(
              currentSpeed: animatedSpeed,
              recommendedSpeed: widget.recommendedSpeed,
              color: widget.color,
              isTracking: widget.isTracking,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "$animatedSpeed",
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      color: widget.color,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    "km/h",
                    style: TextStyle(fontSize: 18, color: Colors.white54),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.color, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag, size: 16, color: widget.color),
                        SizedBox(width: 4),
                        Text(
                          "${widget.recommendedSpeed} km/h",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: widget.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class SpeedometerPainter extends CustomPainter {
  final int currentSpeed;
  final int recommendedSpeed;
  final Color color;
  final bool isTracking;

  SpeedometerPainter({
    required this.currentSpeed,
    required this.recommendedSpeed,
    required this.color,
    required this.isTracking,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 15;

    final borderPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8;
    canvas.drawCircle(center, radius - 15, borderPaint);

    final bgPaint =
        Paint()
          ..color = Color(0xFF2A2A2A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 25
          ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      bgPaint,
    );

    final maxSpeed = 180.0;
    final speedRatio = (currentSpeed / maxSpeed).clamp(0.0, 1.0);
    final sweepAngle = math.pi * 1.5 * speedRatio;

    if (currentSpeed > 0) {
      final needlePaint =
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round;

      final needleStart = Offset(
        center.dx + (radius - 40) * math.cos(math.pi * 0.75 + sweepAngle - 0.1),
        center.dy + (radius - 40) * math.sin(math.pi * 0.75 + sweepAngle - 0.1),
      );
      final needleEnd = Offset(
        center.dx + (radius - 10) * math.cos(math.pi * 0.75 + sweepAngle),
        center.dy + (radius - 10) * math.sin(math.pi * 0.75 + sweepAngle),
      );
      canvas.drawLine(needleStart, needleEnd, needlePaint);

      final dotPaint =
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 12, dotPaint);
    }

    final recRatio = (recommendedSpeed / maxSpeed).clamp(0.0, 1.0);
    final recAngle = math.pi * 0.75 + (math.pi * 1.5 * recRatio);
    final recPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;

    final recStart = Offset(
      center.dx + (radius - 15) * math.cos(recAngle),
      center.dy + (radius - 15) * math.sin(recAngle),
    );
    final recEnd = Offset(
      center.dx + (radius + 12) * math.cos(recAngle),
      center.dy + (radius + 12) * math.sin(recAngle),
    );
    canvas.drawLine(recStart, recEnd, recPaint);

    for (int i = 0; i <= 6; i++) {
      final speed = (i * 30).toString();
      final angle = math.pi * 0.75 + (math.pi * 1.5 * i / 6);
      final textRadius = radius - 55;
      final textPos = Offset(
        center.dx + textRadius * math.cos(angle) - 12,
        center.dy + textRadius * math.sin(angle) - 12,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: speed,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, textPos);
    }
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter oldDelegate) {
    return oldDelegate.currentSpeed != currentSpeed ||
        oldDelegate.recommendedSpeed != recommendedSpeed ||
        oldDelegate.color != color ||
        oldDelegate.isTracking != isTracking;
  }
}

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
