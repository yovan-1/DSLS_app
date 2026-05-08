import 'package:flutter/material.dart' hide DayPeriod;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import '../models/speed_calculator.dart';

class SpeedAlertService extends ChangeNotifier {
  int _alertThreshold = 10;
  bool _enableSound = true;
  bool _enableVibration = true;
  bool _enableVoice = true;
  bool _enableNotifications = true;
  bool _enableZoneAlerts = true;
  int _warningAheadSpeed = 5;
  int _criticalAheadSpeed = 15;

  AlertLevel _lastAlertLevel = AlertLevel.safe;
  DateTime? _lastAlertTime;
  DateTime? _lastZoneApproachingTime;
  DateTime? _lastZoneEnteringTime;
  LocationType? _lastZoneType;

  bool _ttsInitialized = false;
  bool _ttsAvailable = false;
  int _ttsAttempts = 0;
  static const int _maxTtsAttempts = 2;

  static const _alertCooldown = Duration(seconds: 5);
  static const _zoneApproachingCooldown = Duration(seconds: 60);
  static const _zoneEnteringCooldown = Duration(seconds: 30);

  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  SpeedAlertService() {
    _initTts();
  }

  int get alertThreshold => _alertThreshold;
  bool get enableSound => _enableSound;
  bool get enableVibration => _enableVibration;
  bool get enableVoice => _enableVoice;
  bool get enableNotifications => _enableNotifications;
  bool get enableZoneAlerts => _enableZoneAlerts;
  int get warningAheadSpeed => _warningAheadSpeed;
  int get criticalAheadSpeed => _criticalAheadSpeed;
  bool get ttsAvailable => _ttsAvailable;
  bool get ttsInitialized => _ttsInitialized;

  void setAlertThreshold(int value) {
    _alertThreshold = value.clamp(0, 30);
    notifyListeners();
  }

  void setEnableSound(bool value) {
    _enableSound = value;
    notifyListeners();
  }

  void setEnableVibration(bool value) {
    _enableVibration = value;
    notifyListeners();
  }

  void setEnableVoice(bool value) {
    _enableVoice = value;
    notifyListeners();
  }

  void setEnableNotifications(bool value) {
    _enableNotifications = value;
    notifyListeners();
  }

  void setEnableZoneAlerts(bool value) {
    _enableZoneAlerts = value;
    notifyListeners();
  }

  void setWarningAheadSpeed(int value) {
    _warningAheadSpeed = value.clamp(0, 20);
    notifyListeners();
  }

  void setCriticalAheadSpeed(int value) {
    _criticalAheadSpeed = value.clamp(5, 30);
    notifyListeners();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setSharedInstance(true);
      await _tts.awaitSpeakCompletion(true);

      _tts.setCompletionHandler(() {
        debugPrint('[AlertService] TTS: Completed');
      });

      _tts.setErrorHandler((msg) {
        debugPrint('[AlertService] TTS Error: $msg');
        _ttsAvailable = false;
      });

      _tts.setCancelHandler(() {
        debugPrint('[AlertService] TTS: Cancelled');
      });

      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      try {
        final engines = await _tts.getEngines;
        if (engines != null && engines.isNotEmpty) {
          debugPrint('[AlertService] TTS: Available engines - $engines');
          await _tts.setEngine(engines.first.toString());
        }
      } catch (e) {
        debugPrint('[AlertService] TTS: Engine selection failed - $e');
      }

      _ttsInitialized = true;
      _ttsAvailable = true;
      debugPrint('[AlertService] TTS: Initialized successfully');
    } catch (e) {
      debugPrint('[AlertService] TTS: Init error - $e');
      _ttsInitialized = true;
      _ttsAvailable = false;
    }
  }

  Future<void> testTts() async {
    debugPrint('[AlertService] TTS: Running test');
    await _speakAlert("Testing text to speech. If you hear this, T T S is working correctly.");
  }

  AlertLevel checkSpeed(int currentSpeed, int recommendedSpeed) {
    final diff = currentSpeed - recommendedSpeed;

    if (diff >= _criticalAheadSpeed) {
      return AlertLevel.critical;
    } else if (diff >= _warningAheadSpeed) {
      return AlertLevel.warning;
    } else if (diff > 0) {
      return AlertLevel.caution;
    } else {
      return AlertLevel.safe;
    }
  }

  String getAlertMessage(int currentSpeed, int recommendedSpeed) {
    final diff = currentSpeed - recommendedSpeed;

    if (diff >= _criticalAheadSpeed) {
      return "CRITICAL: You are exceeding the recommended speed by $diff kilometers per hour!";
    } else if (diff >= _warningAheadSpeed) {
      return "Warning: You are $diff kilometers per hour over the recommended speed";
    } else if (diff > 0) {
      return "Caution: Slightly above recommended speed";
    } else {
      return "Speed OK";
    }
  }

  Future<void> triggerAlert(int currentSpeed, int recommendedSpeed) async {
    final alertLevel = checkSpeed(currentSpeed, recommendedSpeed);

    if (alertLevel == AlertLevel.safe || alertLevel == _lastAlertLevel) {
      return;
    }

    if (_lastAlertTime != null) {
      final timeSinceLast = DateTime.now().difference(_lastAlertTime!);
      if (timeSinceLast < _alertCooldown) {
        return;
      }
    }

    _lastAlertLevel = alertLevel;
    _lastAlertTime = DateTime.now();

    if (alertLevel == AlertLevel.critical) {
      if (_enableVibration) {
        await _vibrateCritical();
      }
      if (_enableSound) {
        await _playAlertSound(isCritical: true);
      }
      if (_enableVoice) {
        await _speakAlert(getAlertMessage(currentSpeed, recommendedSpeed));
      }
    } else if (alertLevel == AlertLevel.warning) {
      if (_enableVibration) {
        await _vibrateWarning();
      }
      if (_enableSound) {
        await _playAlertSound(isCritical: false);
      }
      if (_enableVoice) {
        await _speakAlert(getAlertMessage(currentSpeed, recommendedSpeed));
      }
    }

    notifyListeners();
  }

  Future<void> triggerZoneAlert({
    required LocationType zoneType,
    required String zoneName,
    required int speedLimit,
    required bool isApproaching,
  }) async {
    if (!_enableZoneAlerts) return;

    final now = DateTime.now();
    final cooldown = isApproaching ? _zoneApproachingCooldown : _zoneEnteringCooldown;
    final lastTime = isApproaching ? _lastZoneApproachingTime : _lastZoneEnteringTime;

    if (lastTime != null && now.difference(lastTime) < cooldown) {
      return;
    }

    if (zoneType == _lastZoneType && lastTime != null) {
      final timeSince = now.difference(lastTime);
      if (timeSince < const Duration(seconds: 10)) {
        return;
      }
    }

    if (isApproaching) {
      _lastZoneApproachingTime = now;
    } else {
      _lastZoneEnteringTime = now;
    }
    _lastZoneType = zoneType;

    final message = isApproaching
        ? _getZoneApproachingMessage(zoneType, zoneName, speedLimit)
        : _getZoneEnteringMessage(zoneType, zoneName, speedLimit);

    if (_enableVibration) {
      if (isApproaching) {
        await _vibrateZoneApproaching();
      } else {
        await _vibrateZoneEntering();
      }
    }

    if (_enableSound) {
      await _playZoneAlertSound(isApproaching: isApproaching);
    }

    if (_enableVoice) {
      await _speakAlert(message);
    }

    notifyListeners();
  }

  String _getZoneApproachingMessage(LocationType type, String zoneName, int speedLimit) {
    final namePart = zoneName.isNotEmpty ? '$zoneName. ' : '';

    switch (type) {
      case LocationType.schoolZone:
        return 'Approaching school zone. $namePart Reduce speed to $speedLimit kilometers per hour. Watch for children.';
      case LocationType.junction:
        return 'Approaching junction. $namePart Reduce speed to $speedLimit.';
      case LocationType.roundabout:
        return 'Approaching roundabout. $namePart Reduce speed to $speedLimit.';
      case LocationType.residential:
        return 'Entering residential area. $namePart Speed limit $speedLimit.';
      case LocationType.constructionZone:
        return 'Approaching construction zone. $namePart Reduce speed to $speedLimit.';
      case LocationType.urban:
        return 'Approaching urban area. $namePart Reduce speed to $speedLimit.';
      case LocationType.suburban:
        return 'Approaching suburban area. $namePart Reduce speed to $speedLimit.';
      case LocationType.highway:
        return 'Leaving highway. $namePart Reduce speed to $speedLimit.';
    }
  }

  String _getZoneEnteringMessage(LocationType type, String zoneName, int speedLimit) {
    final namePart = zoneName.isNotEmpty ? '$zoneName. ' : '';

    switch (type) {
      case LocationType.schoolZone:
        return 'Entering school zone. $namePart Speed limit $speedLimit kilometers per hour.';
      case LocationType.junction:
        return 'In junction. $namePart Speed limit $speedLimit kilometers per hour.';
      case LocationType.roundabout:
        return 'In roundabout. $namePart Reduce to $speedLimit kilometers per hour.';
      case LocationType.residential:
        return 'In residential zone. $namePart Speed limit $speedLimit kilometers per hour.';
      case LocationType.constructionZone:
        return 'In construction zone. $namePart Speed limit $speedLimit kilometers per hour.';
      case LocationType.urban:
        return 'In urban area. $namePart Speed limit $speedLimit kilometers per hour.';
      default:
        return 'Entering speed zone. $namePart Speed limit $speedLimit kilometers per hour.';
    }
  }

  Future<void> _speakAlert(String message) async {
    if (!_enableVoice) return;

    if (!_ttsAvailable) {
      debugPrint('[AlertService] TTS not available, using fallback');
      await _playFallbackSound();
      return;
    }

    _ttsAttempts = 0;
    while (_ttsAttempts < _maxTtsAttempts) {
      try {
        debugPrint('[AlertService] TTS: Attempt ${_ttsAttempts + 1} - $message');
        await _tts.stop();
        final result = await _tts.speak(message);

        if (result == 1) {
          debugPrint('[AlertService] TTS: Success');
          _ttsAvailable = true;
          return;
        }
      } catch (e) {
        debugPrint('[AlertService] TTS attempt ${_ttsAttempts + 1} failed: $e');
      }
      _ttsAttempts++;
    }

    debugPrint('[AlertService] TTS failed after $_maxTtsAttempts attempts, using fallback');
    _ttsAvailable = false;
    await _playFallbackSound();
  }

  Future<void> _playAlertSound({required bool isCritical}) async {
    try {
      if (isCritical) {
        await _audioPlayer.play(AssetSource('sounds/critical_alert.wav'));
      } else {
        await _audioPlayer.play(AssetSource('sounds/warning_alert.wav'));
      }
    } catch (e) {
      debugPrint('[AlertService] Sound play error: $e');
    }
  }

  Future<void> _playZoneAlertSound({required bool isApproaching}) async {
    try {
      await _audioPlayer.setVolume(isApproaching ? 0.5 : 0.8);
      await _audioPlayer.play(AssetSource('sounds/warning_alert.wav'));
      await _audioPlayer.setVolume(1.0);
    } catch (e) {
      debugPrint('[AlertService] Zone sound play error: $e');
    }
  }

  Future<void> _playFallbackSound() async {
    try {
      debugPrint('[AlertService] Playing fallback sound');
      await _audioPlayer.play(AssetSource('sounds/alert_fallback.wav'));
    } catch (e) {
      debugPrint('[AlertService] Fallback sound error: $e');
    }
  }

  Future<void> _vibrateCritical() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 300, 100, 300, 100, 300]);
      }
    } catch (e) {
      debugPrint('[AlertService] Vibration error: $e');
    }
  }

  Future<void> _vibrateWarning() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
    } catch (e) {
      debugPrint('[AlertService] Vibration error: $e');
    }
  }

  Future<void> _vibrateZoneApproaching() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(duration: 100);
      }
    } catch (e) {
      debugPrint('[AlertService] Vibration error: $e');
    }
  }

  Future<void> _vibrateZoneEntering() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(duration: 200);
      }
    } catch (e) {
      debugPrint('[AlertService] Vibration error: $e');
    }
  }

  void resetAlertState() {
    _lastAlertLevel = AlertLevel.safe;
    _lastAlertTime = null;
    _lastZoneApproachingTime = null;
    _lastZoneEnteringTime = null;
    _lastZoneType = null;
    _ttsAttempts = 0;
  }

  @override
  void dispose() {
    _tts.stop();
    _audioPlayer.dispose();
    super.dispose();
  }
}

enum AlertLevel { safe, caution, warning, critical }

class AlertSettings {
  final int threshold;
  final bool sound;
  final bool vibration;
  final bool voice;
  final bool notifications;
  final bool zoneAlerts;
  final int warningAhead;
  final int criticalAhead;

  const AlertSettings({
    required this.threshold,
    required this.sound,
    required this.vibration,
    this.voice = true,
    required this.notifications,
    this.zoneAlerts = true,
    required this.warningAhead,
    required this.criticalAhead,
  });

  Map<String, dynamic> toJson() => {
    'threshold': threshold,
    'sound': sound,
    'vibration': vibration,
    'voice': voice,
    'notifications': notifications,
    'zoneAlerts': zoneAlerts,
    'warningAhead': warningAhead,
    'criticalAhead': criticalAhead,
  };

  factory AlertSettings.fromJson(Map<String, dynamic> json) => AlertSettings(
    threshold: json['threshold'] ?? 10,
    sound: json['sound'] ?? true,
    vibration: json['vibration'] ?? true,
    voice: json['voice'] ?? true,
    notifications: json['notifications'] ?? true,
    zoneAlerts: json['zoneAlerts'] ?? true,
    warningAhead: json['warningAhead'] ?? 5,
    criticalAhead: json['criticalAhead'] ?? 15,
  );
}
