import 'package:flutter/material.dart' hide DayPeriod;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

class SpeedAlertService extends ChangeNotifier {
  int _alertThreshold = 10;
  bool _enableSound = true;
  bool _enableVibration = true;
  bool _enableVoice = true;
  bool _enableNotifications = true;
  int _warningAheadSpeed = 5;
  int _criticalAheadSpeed = 15;

  AlertLevel _lastAlertLevel = AlertLevel.safe;
  DateTime? _lastAlertTime;
  static const _alertCooldown = Duration(seconds: 5);

  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  int get alertThreshold => _alertThreshold;
  bool get enableSound => _enableSound;
  bool get enableVibration => _enableVibration;
  bool get enableVoice => _enableVoice;
  bool get enableNotifications => _enableNotifications;
  int get warningAheadSpeed => _warningAheadSpeed;
  int get criticalAheadSpeed => _criticalAheadSpeed;

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

  void setWarningAheadSpeed(int value) {
    _warningAheadSpeed = value.clamp(0, 20);
    notifyListeners();
  }

  void setCriticalAheadSpeed(int value) {
    _criticalAheadSpeed = value.clamp(5, 30);
    notifyListeners();
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
      return "CRITICAL: You are exceeding the recommended speed by $diff km/h!";
    } else if (diff >= _warningAheadSpeed) {
      return "Warning: You are $diff km/h over the recommended speed";
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

  Future<void> _playAlertSound({required bool isCritical}) async {
    try {
      if (isCritical) {
        await _audioPlayer.play(AssetSource('sounds/critical_alert.wav'));
      } else {
        await _audioPlayer.play(AssetSource('sounds/warning_alert.wav'));
      }
    } catch (e) {
      // Sound file not available - skip
    }
  }

  Future<void> _speakAlert(String message) async {
    try {
      await _tts.stop();
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.speak(message);
    } catch (e) {
      // Text-to-speech not available - skip voice alert
    }
  }

  Future<void> _vibrateCritical() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 300, 100, 300, 100, 300]);
      }
    } catch (e) {
      // Vibration not available
    }
  }

  Future<void> _vibrateWarning() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }
    } catch (e) {
      // Vibration not available
    }
  }

  void resetAlertState() {
    _lastAlertLevel = AlertLevel.safe;
    _lastAlertTime = null;
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
  final int warningAhead;
  final int criticalAhead;

  const AlertSettings({
    required this.threshold,
    required this.sound,
    required this.vibration,
    this.voice = true,
    required this.notifications,
    required this.warningAhead,
    required this.criticalAhead,
  });

  Map<String, dynamic> toJson() => {
    'threshold': threshold,
    'sound': sound,
    'vibration': vibration,
    'voice': voice,
    'notifications': notifications,
    'warningAhead': warningAhead,
    'criticalAhead': criticalAhead,
  };

  factory AlertSettings.fromJson(Map<String, dynamic> json) => AlertSettings(
    threshold: json['threshold'] ?? 10,
    sound: json['sound'] ?? true,
    vibration: json['vibration'] ?? true,
    voice: json['voice'] ?? true,
    notifications: json['notifications'] ?? true,
    warningAhead: json['warningAhead'] ?? 5,
    criticalAhead: json['criticalAhead'] ?? 15,
  );
}
