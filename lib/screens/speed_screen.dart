import 'package:flutter/material.dart' hide DayPeriod;
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
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
import '../widgets/speedometer_widget.dart';
import '../widgets/zone_alert_widget.dart';
import '../widgets/parameter_cards.dart';
import '../widgets/over_speed_flash.dart';
import '../widgets/gps_status_banner.dart';
import '../widgets/condition_status_card.dart';

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
    _recordTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!gpsService.isTracking) {
        _stopRecording(tripService, visibilityService);
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
        autoParams.updateLocationType(speedService.locationResult);
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
      } else {
        final locationResult = speedService.locationResult;
        if (locationResult.status == LocationSpeedStatus.approachingZone) {
          alertService.triggerZoneAlert(
            zoneType: locationResult.locationType,
            zoneName: locationResult.activeZoneName,
            speedLimit: locationResult.speedLimit,
            isApproaching: true,
          );
        } else if (locationResult.status == LocationSpeedStatus.inZone) {
          alertService.triggerZoneAlert(
            zoneType: locationResult.locationType,
            zoneName: locationResult.activeZoneName,
            speedLimit: locationResult.speedLimit,
            isApproaching: false,
          );
        }
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

  void _stopRecording(TripService tripService, VisibilityService visibilityService) {
    _recordTimer?.cancel();
    _recordTimer = null;
    visibilityService.stop();
    tripService.endTrip();
    debugPrint('[SpeedScreen] Recording stopped');
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    super.dispose();
  }

  Color _getSpeedColor(int currentSpeed, int recommendedSpeed) {
    if (currentSpeed == 0) return Colors.grey;
    final diff = currentSpeed - recommendedSpeed;
    if (diff <= 0) return Colors.green;
    if (diff <= 10) return Colors.yellow;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final gpsService = context.watch<GpsSpeedService>();
    final autoParams = context.watch<AutoParametersService>();
    final visibilityService = context.watch<VisibilityService>();
    final tripService = context.watch<TripService>();
    final speedService = context.watch<SpeedService>();

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
                GpsStatusBanner(
                  gpsStatus: gpsStatus,
                  errorMessage: errorMessage,
                  onRetry: () => gpsService.checkPermission(),
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
                _buildOverSpeedAlert(currentSpeed, recommendedSpeed),
                _buildWarnings(warnings),
                _buildStartStopButton(
                  isMonitoring,
                  gpsService,
                  autoParams,
                  recommendedSpeed,
                  tripService,
                  speedService,
                  visibilityService,
                ),
                SizedBox(height: 20),
                ParameterCards(params: params),
                SizedBox(height: 10),
                ConditionStatusCard(
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
              child: OverSpeedFlash(diff: overSpeedDiff),
            ),
        ],
      ),
    );
  }

  Widget _buildOverSpeedAlert(int currentSpeed, int recommendedSpeed) {
    if (currentSpeed <= recommendedSpeed) return SizedBox.shrink();

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
    );
  }

  Widget _buildWarnings(List<String> warnings) {
    if (warnings.isEmpty) return SizedBox.shrink();

    return Column(
      children: warnings.map((w) => Container(
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
      )).toList(),
    );
  }

  Widget _buildStartStopButton(
    bool isMonitoring,
    GpsSpeedService gpsService,
    AutoParametersService autoParams,
    int recommendedSpeed,
    TripService tripService,
    SpeedService speedService,
    VisibilityService visibilityService,
  ) {
    return ElevatedButton(
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
          _stopRecording(tripService, visibilityService);
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
    );
  }
}
