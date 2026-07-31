import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AlertSettings {
  final int alertThreshold;
  final bool enableSound;
  final bool enableVibration;
  final bool enableVoice;
  final bool enableNotifications;
  final bool enableZoneAlerts;
  final int warningAheadSpeed;
  final int criticalAheadSpeed;

  const AlertSettings({
    this.alertThreshold = 10,
    this.enableSound = true,
    this.enableVibration = true,
    this.enableVoice = true,
    this.enableNotifications = true,
    this.enableZoneAlerts = true,
    this.warningAheadSpeed = 10,
    this.criticalAheadSpeed = 20,
  });

  AlertSettings copyWith({
    int? alertThreshold,
    bool? enableSound,
    bool? enableVibration,
    bool? enableVoice,
    bool? enableNotifications,
    bool? enableZoneAlerts,
    int? warningAheadSpeed,
    int? criticalAheadSpeed,
  }) {
    return AlertSettings(
      alertThreshold: alertThreshold ?? this.alertThreshold,
      enableSound: enableSound ?? this.enableSound,
      enableVibration: enableVibration ?? this.enableVibration,
      enableVoice: enableVoice ?? this.enableVoice,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      enableZoneAlerts: enableZoneAlerts ?? this.enableZoneAlerts,
      warningAheadSpeed: warningAheadSpeed ?? this.warningAheadSpeed,
      criticalAheadSpeed: criticalAheadSpeed ?? this.criticalAheadSpeed,
    );
  }

  Map<String, dynamic> toJson() => {
    'alertThreshold': alertThreshold,
    'enableSound': enableSound,
    'enableVibration': enableVibration,
    'enableVoice': enableVoice,
    'enableNotifications': enableNotifications,
    'enableZoneAlerts': enableZoneAlerts,
    'warningAheadSpeed': warningAheadSpeed,
    'criticalAheadSpeed': criticalAheadSpeed,
  };

  factory AlertSettings.fromJson(Map<String, dynamic> json) => AlertSettings(
    alertThreshold: json['alertThreshold'] ?? 10,
    enableSound: json['enableSound'] ?? true,
    enableVibration: json['enableVibration'] ?? true,
    enableVoice: json['enableVoice'] ?? true,
    enableNotifications: json['enableNotifications'] ?? true,
    enableZoneAlerts: json['enableZoneAlerts'] ?? true,
    warningAheadSpeed: json['warningAheadSpeed'] ?? 10,
    criticalAheadSpeed: json['criticalAheadSpeed'] ?? 20,
  );
}

class AwsCredentials {
  final String accessKey;
  final String secretKey;
  final String bucketName;
  final String region;

  const AwsCredentials({
    required this.accessKey,
    required this.secretKey,
    this.bucketName = 'dsls-trip-data',
    this.region = 'us-east-1',
  });

  Map<String, dynamic> toJson() => {
    'accessKey': accessKey,
    'secretKey': secretKey,
    'bucketName': bucketName,
    'region': region,
  };

  factory AwsCredentials.fromJson(Map<String, dynamic> json) => AwsCredentials(
    accessKey: json['accessKey'] ?? '',
    secretKey: json['secretKey'] ?? '',
    bucketName: json['bucketName'] ?? 'dsls-trip-data',
    region: json['region'] ?? 'us-east-1',
  );
}

class SettingsService extends ChangeNotifier {
  static const String _keyAlertSettings = 'alert_settings';
  static const String _keyAwsCredentials = 'aws_credentials_encrypted';
  static const String _keyAutoUpload = 'auto_upload_enabled';
  static const String _keyFirstLaunch = 'first_launch_done';
  static const String _keyKeepScreenOn = 'keep_screen_on';

  static const _secureStorage = FlutterSecureStorage();
  static const String _keyMasterSecret = 'aws_cred_master_key';

  SharedPreferences? _prefs;
  bool _isInitialized = false;
  bool _autoUploadEnabled = false;
  bool _keepScreenOn = true;

  bool get isInitialized => _isInitialized;
  bool get autoUploadEnabled => _autoUploadEnabled;

  /// Whether to hold the screen awake during a drive. On by default: the
  /// common case is a cradled phone the driver glances at.
  bool get keepScreenOn => _keepScreenOn;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _autoUploadEnabled = _prefs?.getBool(_keyAutoUpload) ?? false;
    _keepScreenOn = _prefs?.getBool(_keyKeepScreenOn) ?? true;
    _isInitialized = true;
  }

  Future<AlertSettings> loadAlertSettings() async {
    try {
      final json = _prefs?.getString(_keyAlertSettings);
      if (json == null) return const AlertSettings();
      return AlertSettings.fromJson(jsonDecode(json));
    } catch (e) {
      debugPrint('[Settings] Error loading alert settings: $e');
      return const AlertSettings();
    }
  }

  Future<void> saveAlertSettings(AlertSettings settings) async {
    try {
      final json = jsonEncode(settings.toJson());
      await _prefs?.setString(_keyAlertSettings, json);
      notifyListeners();
    } catch (e) {
      debugPrint('[Settings] Error saving alert settings: $e');
    }
  }

  Future<void> setAutoUpload(bool enabled) async {
    await _prefs?.setBool(_keyAutoUpload, enabled);
    _autoUploadEnabled = enabled;
    notifyListeners();
  }

  Future<void> setKeepScreenOn(bool enabled) async {
    await _prefs?.setBool(_keyKeepScreenOn, enabled);
    _keepScreenOn = enabled;
    notifyListeners();
  }

  Future<encrypt.Key> _getEncryptionKey() async {
    String? stored = await _secureStorage.read(key: _keyMasterSecret);
    if (stored == null) {
      final randomBytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      stored = base64Encode(randomBytes);
      await _secureStorage.write(key: _keyMasterSecret, value: stored);
    }
    return encrypt.Key.fromBase64(stored);
  }

  Future<void> saveAwsCredentials(AwsCredentials credentials) async {
    try {
      final key = await _getEncryptionKey();
      // A fresh random IV per write. The previous IV.fromLength(16) produced 16
      // zero bytes reused for every save, making AES-CBC ciphertext
      // deterministic. The IV is stored alongside the payload below, so old
      // blobs still decrypt.
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final json = jsonEncode(credentials.toJson());
      final encrypted = encrypter.encrypt(json, iv: iv);

      final combined = {
        'iv': iv.base64,
        'data': encrypted.base64,
      };

      await _prefs?.setString(_keyAwsCredentials, jsonEncode(combined));
      notifyListeners();
    } catch (e) {
      // Rethrow: swallowing here made the UI report "saved securely" when
      // nothing was written. CloudSyncScreen already has an error path.
      debugPrint('[Settings] Error encrypting AWS credentials: $e');
      rethrow;
    }
  }

  Future<AwsCredentials?> getAwsCredentials() async {
    try {
      final stored = _prefs?.getString(_keyAwsCredentials);
      if (stored == null) return null;

      final combined = jsonDecode(stored) as Map<String, dynamic>;
      final iv = encrypt.IV.fromBase64(combined['iv']);
      final encrypted = encrypt.Encrypted.fromBase64(combined['data']);

      final key = await _getEncryptionKey();
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final decrypted = encrypter.decrypt(encrypted, iv: iv);
      return AwsCredentials.fromJson(jsonDecode(decrypted));
    } catch (e) {
      debugPrint('[Settings] Error decrypting AWS credentials: $e');
      return null;
    }
  }

  Future<bool> hasAwsCredentials() async {
    final creds = await getAwsCredentials();
    return creds != null && creds.accessKey.isNotEmpty;
  }

  Future<bool> isFirstLaunch() async {
    return !(_prefs?.getBool(_keyFirstLaunch) ?? false);
  }

  Future<void> markFirstLaunchComplete() async {
    await _prefs?.setBool(_keyFirstLaunch, true);
  }
}
