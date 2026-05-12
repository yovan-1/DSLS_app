import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/trip_data.dart';
import 'settings_service.dart';

class CloudUploadService extends ChangeNotifier {
  final SettingsService _settingsService;
  
  static const String _defaultBucket = 'dsls-trip-data';
  static const String _defaultRegion = 'us-east-1';
  static const String _apiVersion = '2023-01-01';

  bool _isUploading = false;
  bool _testInProgress = false;
  String? _lastError;
  List<String> _uploadHistory = [];
  final List<TripData> _pendingUploads = [];

  CloudUploadService({required SettingsService settingsService})
      : _settingsService = settingsService;

  bool get isUploading => _isUploading;
  bool get testInProgress => _testInProgress;
  String? get lastError => _lastError;
  List<String> get uploadHistory => List.unmodifiable(_uploadHistory);
  int get pendingCount => _pendingUploads.length;

  Future<bool> uploadTrip(TripData trip, {List<LatLng>? routePath}) async {
    final credentials = await _settingsService.getAwsCredentials();
    if (credentials == null) {
      _lastError = 'AWS credentials not configured';
      return false;
    }

    _isUploading = true;
    _lastError = null;
    notifyListeners();

    try {
      final tripJson = _buildTripJson(trip, routePath);
      final tripKey = 'trips/${trip.id}.json';
      
      final success = await _uploadToS3(
        credentials: credentials,
        key: tripKey,
        data: utf8.encode(jsonEncode(tripJson)),
        contentType: 'application/json',
      );

      if (success && routePath != null && routePath.isNotEmpty) {
        final pathJson = _buildPathJson(trip.id, routePath);
        final pathKey = 'trips/${trip.id}-path.json';
        
        await _uploadToS3(
          credentials: credentials,
          key: pathKey,
          data: utf8.encode(jsonEncode(pathJson)),
          contentType: 'application/json',
        );
      }

      _uploadHistory.insert(0, '${DateTime.now().toIso8601String()}: ${trip.id}');
      if (_uploadHistory.length > 50) {
        _uploadHistory.removeLast();
      }

      _isUploading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _lastError = e.toString();
      _isUploading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadTrips(List<TripData> trips) async {
    bool allSuccess = true;
    for (final trip in trips) {
      final success = await uploadTrip(trip);
      if (!success) allSuccess = false;
    }
    return allSuccess;
  }

  Future<bool> testConnection() async {
    final credentials = await _settingsService.getAwsCredentials();
    if (credentials == null) {
      _lastError = 'AWS credentials not configured';
      return false;
    }

    _testInProgress = true;
    _lastError = null;
    notifyListeners();

    try {
      final testKey = 'config/connection-test-${const Uuid().v4()}.json';
      final testData = utf8.encode(jsonEncode({
        'test': true,
        'timestamp': DateTime.now().toIso8601String(),
      }));

      final success = await _uploadToS3(
        credentials: credentials,
        key: testKey,
        data: testData,
        contentType: 'application/json',
      );

      if (success) {
        await _deleteFromS3(credentials, testKey);
      }

      _testInProgress = false;
      notifyListeners();
      return success;
    } catch (e) {
      _lastError = e.toString();
      _testInProgress = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> syncPendingUploads() async {
    if (_pendingUploads.isEmpty) return;

    final pending = List<TripData>.from(_pendingUploads);
    _pendingUploads.clear();

    for (final trip in pending) {
      final success = await uploadTrip(trip);
      if (!success) {
        _pendingUploads.add(trip);
      }
    }

    notifyListeners();
  }

  void addToPending(TripData trip) {
    _pendingUploads.add(trip);
    notifyListeners();
  }

  Map<String, dynamic> _buildTripJson(TripData trip, List<LatLng>? routePath) {
    return {
      'id': trip.id,
      'startTime': trip.startTime.toIso8601String(),
      'endTime': trip.endTime?.toIso8601String(),
      'location': {
        'type': trip.location.name,
        'baseSpeedLimit': trip.baseSpeedLimit,
      },
      'speeds': {
        'recommended': trip.recommendedSpeed,
        'max': trip.maxSpeed,
        'avg': trip.avgSpeed,
      },
      'safety': {
        'overSpeedCount': trip.overSpeedCount,
        'avgRiskScore': trip.avgRiskScore,
        'alerts': trip.alerts.map((a) => a.toJson()).toList(),
      },
      'roadAnalytics': {
        'roadSegmentId': trip.roadSegmentId,
        'actualSpeedLimit': trip.actualSpeedLimit,
        'estimatedSurface': trip.estimatedSurface,
        'distanceTraveledMeters': trip.distanceTraveledMeters,
      },
      'hasRoutePath': routePath != null && routePath.isNotEmpty,
      'uploadedAt': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _buildPathJson(String tripId, List<LatLng> routePath) {
    return {
      'tripId': tripId,
      'path': routePath.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
      'pointCount': routePath.length,
      'recordedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<bool> _uploadToS3({
    required AwsCredentials credentials,
    required String key,
    required Uint8List data,
    required String contentType,
  }) async {
    final host = '${credentials.bucketName}.s3.${credentials.region}.amazonaws.com';
    final url = Uri.parse('https://$host/$key');

    final hash = _calculateSignature(
      credentials.secretKey,
      'PUT',
      contentType,
      DateTime.now().toUtc().toIso8601String(),
      '/$key',
    );

    try {
      final response = await http.put(
        url,
        headers: {
          'Content-Type': contentType,
          'Content-Length': data.length.toString(),
          'Authorization': 'AWS ${credentials.accessKey}:$hash',
          'x-amz-date': DateTime.now().toUtc().toIso8601String(),
        },
        body: data,
      ).timeout(const Duration(seconds: 30));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<void> _deleteFromS3(AwsCredentials credentials, String key) async {
    final host = '${credentials.bucketName}.s3.${credentials.region}.amazonaws.com';
    final url = Uri.parse('https://$host/$key');

    try {
      await http.delete(
        url,
        headers: {
          'Authorization': 'AWS ${credentials.accessKey}:signature',
        },
      );
    } catch (_) {}
  }

  String _calculateSignature(
    String secretKey,
    String method,
    String contentType,
    String date,
    String canonicalUri,
  ) {
    final stringToSign = '$method\n\n$contentType\n$date\n$canonicalUri';
    return base64.encode(utf8.encode(stringToSign));
  }
}

class LatLng {
  final double latitude;
  final double longitude;

  const LatLng({required this.latitude, required this.longitude});
}
