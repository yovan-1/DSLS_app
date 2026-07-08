import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/trip_data.dart';
import 'settings_service.dart';

class CloudUploadService extends ChangeNotifier {
  final SettingsService _settingsService;

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
    try {
      final response = await _signedS3Request(
        credentials: credentials,
        method: 'PUT',
        key: key,
        body: data,
        contentType: contentType,
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<void> _deleteFromS3(AwsCredentials credentials, String key) async {
    try {
      await _signedS3Request(credentials: credentials, method: 'DELETE', key: key);
    } catch (_) {}
  }

  String _formatAmzDate(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  String _formatDateStamp(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}';
  }

  List<int> _hmacSha256(List<int> key, List<int> message) =>
      Hmac(sha256, key).convert(message).bytes;

  List<int> _getSignatureKey(
    String secretKey,
    String dateStamp,
    String region,
    String service,
  ) {
    final kDate = _hmacSha256(utf8.encode('AWS4$secretKey'), utf8.encode(dateStamp));
    final kRegion = _hmacSha256(kDate, utf8.encode(region));
    final kService = _hmacSha256(kRegion, utf8.encode(service));
    return _hmacSha256(kService, utf8.encode('aws4_request'));
  }

  Future<http.Response> _signedS3Request({
    required AwsCredentials credentials,
    required String method,
    required String key,
    Uint8List? body,
    String? contentType,
  }) async {
    final payload = body ?? Uint8List(0);
    final host = '${credentials.bucketName}.s3.${credentials.region}.amazonaws.com';
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final dateStamp = _formatDateStamp(now);
    final payloadHash = sha256.convert(payload).toString();
    final canonicalUri = '/$key';
    final canonicalHeaders =
        'host:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n';
    const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

    final canonicalRequest =
        '$method\n$canonicalUri\n\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
    final credentialScope = '$dateStamp/${credentials.region}/s3/aws4_request';
    final hashedCanonicalRequest = sha256.convert(utf8.encode(canonicalRequest)).toString();
    final stringToSign =
        'AWS4-HMAC-SHA256\n$amzDate\n$credentialScope\n$hashedCanonicalRequest';

    final signingKey = _getSignatureKey(
      credentials.secretKey,
      dateStamp,
      credentials.region,
      's3',
    );
    final signature = _hmacSha256(signingKey, utf8.encode(stringToSign))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final authorization = 'AWS4-HMAC-SHA256 '
        'Credential=${credentials.accessKey}/$credentialScope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';

    final headers = <String, String>{
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      'Authorization': authorization,
      if (contentType != null) 'Content-Type': contentType,
    };

    final url = Uri.parse('https://$host/$key');
    if (method == 'PUT') {
      return http
          .put(url, headers: headers, body: payload)
          .timeout(const Duration(seconds: 30));
    }
    return http.delete(url, headers: headers).timeout(const Duration(seconds: 30));
  }
}

class LatLng {
  final double latitude;
  final double longitude;

  const LatLng({required this.latitude, required this.longitude});
}
