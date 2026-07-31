import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/trip_data.dart';
import 'settings_service.dart';
import 'trip_repository.dart';

class CloudUploadService extends ChangeNotifier {
  final SettingsService _settingsService;

  /// Where the queue and history live. Without it the service still uploads,
  /// but nothing is remembered across a restart — which is what it did before.
  TripRepository? _repository;

  /// Retries per trip before it stops being attempted. Bounded so a trip S3
  /// will never accept does not get retried on every launch for ever.
  static const int maxAttempts = 5;

  bool _isUploading = false;
  bool _testInProgress = false;
  String? _lastError;
  int _pendingCount = 0;
  List<UploadHistoryEntry> _uploadHistory = const [];

  CloudUploadService({required SettingsService settingsService})
      : _settingsService = settingsService;

  bool get isUploading => _isUploading;
  bool get testInProgress => _testInProgress;
  String? get lastError => _lastError;
  List<UploadHistoryEntry> get uploadHistory => List.unmodifiable(_uploadHistory);
  int get pendingCount => _pendingCount;

  void setRepository(TripRepository repository) {
    _repository = repository;
  }

  /// Loads the persisted queue and history. Call once at startup.
  Future<void> init() async {
    await _refreshQueueState();
  }

  Future<void> _refreshQueueState() async {
    final repository = _repository;
    if (repository == null) return;
    _pendingCount = await repository.pendingUploadCount();
    _uploadHistory = await repository.uploadHistory();
    notifyListeners();
  }

  /// Uploads a trip, recording the outcome.
  ///
  /// On failure the trip is queued rather than dropped. Previously `endTrip`
  /// fired this and discarded the result, so a trip that failed to upload was
  /// simply never uploaded and nothing recorded that it had been tried.
  Future<bool> uploadTrip(TripData trip, {List<LatLng>? routePath}) async {
    final credentials = await _settingsService.getAwsCredentials();
    if (credentials == null) {
      _lastError = _settingsService.credentialsNeedReentry
          ? 'Saved AWS credentials could not be read — please enter them again'
          : 'AWS credentials not configured';
      notifyListeners();
      await _queueForRetry(trip.id, _lastError!);
      return false;
    }

    _isUploading = true;
    _lastError = null;
    notifyListeners();

    try {
      // Prefer the route actually recorded for this trip over anything passed
      // in. Nothing ever passed one, which is why the "GPS route path" the UI
      // advertised was never uploaded.
      final path = routePath ?? await _recordedRoute(trip.id);

      final tripJson = _buildTripJson(trip, path);
      final tripKey = 'trips/${trip.id}.json';

      final success = await _uploadToS3(
        credentials: credentials,
        key: tripKey,
        data: utf8.encode(jsonEncode(tripJson)),
        contentType: 'application/json',
      );

      if (success && path != null && path.isNotEmpty) {
        final pathJson = _buildPathJson(trip.id, path);
        final pathKey = 'trips/${trip.id}-path.json';

        await _uploadToS3(
          credentials: credentials,
          key: pathKey,
          data: utf8.encode(jsonEncode(pathJson)),
          contentType: 'application/json',
        );
      }

      _isUploading = false;

      if (success) {
        await _repository?.dequeueUpload(trip.id);
        await _repository?.addUploadHistory(trip.id, succeeded: true);
      } else {
        await _queueForRetry(trip.id, _lastError ?? 'Upload failed');
      }

      await _refreshQueueState();
      notifyListeners();
      return success;
    } catch (e) {
      _lastError = e.toString();
      _isUploading = false;
      await _queueForRetry(trip.id, _lastError!);
      await _refreshQueueState();
      notifyListeners();
      return false;
    }
  }

  Future<void> _queueForRetry(String tripId, String error) async {
    final repository = _repository;
    if (repository == null) return;
    await repository.enqueueUpload(tripId);
    await repository.recordUploadFailure(tripId, error);
    await repository.addUploadHistory(tripId, succeeded: false, detail: error);
  }

  /// The route recorded during the drive, from the per-second driving records.
  Future<List<LatLng>?> _recordedRoute(String tripId) async {
    final repository = _repository;
    if (repository == null) return null;
    final points = await repository.routeFor(tripId);
    if (points.isEmpty) return null;
    return points
        .map((p) => LatLng(latitude: p.latitude, longitude: p.longitude))
        .toList();
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

  /// Uploads everything waiting in the queue, oldest first.
  ///
  /// Returns how many succeeded. Safe to call repeatedly: entries that fail
  /// stay queued with an incremented attempt count, and stop being retried once
  /// they pass [maxAttempts].
  ///
  /// The previous version drained an in-memory list that nothing ever added to,
  /// so it was a permanent no-op.
  Future<int> syncPendingUploads() async {
    final repository = _repository;
    if (repository == null || _isDraining) return 0;

    _isDraining = true;
    try {
      final pending = await repository.pendingUploads(maxAttempts: maxAttempts);
      if (pending.isEmpty) return 0;

      final trips = await repository.loadTrips();
      final byId = {for (final trip in trips) trip.id: trip};

      var uploaded = 0;
      for (final queued in pending) {
        final trip = byId[queued.tripId];
        if (trip == null) {
          // The trip was deleted while queued; nothing left to upload.
          await repository.dequeueUpload(queued.tripId);
          continue;
        }
        if (await uploadTrip(trip)) uploaded++;
      }

      await _refreshQueueState();
      return uploaded;
    } finally {
      _isDraining = false;
    }
  }

  bool _isDraining = false;

  /// Queues a trip without attempting it now — used when there is no network.
  Future<void> addToPending(TripData trip) async {
    await _repository?.enqueueUpload(trip.id);
    await _refreshQueueState();
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

      if (response.statusCode >= 200 && response.statusCode < 300) return true;

      // A non-2xx used to return false leaving `_lastError` null, so a failure
      // was not merely unreported — it was unknowable. S3 puts the reason in
      // an XML body; surface it.
      _lastError = _describeS3Error(response.statusCode, response.body);
      return false;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// Pulls `<Code>` and `<Message>` out of an S3 error body.
  ///
  /// Deliberately a small regex rather than an XML dependency: the shape is
  /// fixed and this must never throw while reporting another failure.
  static String _describeS3Error(int statusCode, String body) {
    final code = RegExp(r'<Code>(.*?)</Code>').firstMatch(body)?.group(1);
    final message = RegExp(r'<Message>(.*?)</Message>').firstMatch(body)?.group(1);

    if (code == null && message == null) {
      return 'S3 returned HTTP $statusCode';
    }
    return 'S3 $statusCode ${code ?? ''}: ${message ?? ''}'.trim();
  }

  Future<void> _deleteFromS3(AwsCredentials credentials, String key) async {
    try {
      await _signedS3Request(credentials: credentials, method: 'DELETE', key: key);
    } catch (e) {
      // Only ever used to tidy up a connection-test object. Worth a line in the
      // log rather than an empty catch, but not worth failing the test over.
      debugPrint('[CloudUpload] Could not delete $key: $e');
    }
  }

  static String _formatAmzDate(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  static String _formatDateStamp(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}';
  }

  static List<int> _hmacSha256(List<int> key, List<int> message) =>
      Hmac(sha256, key).convert(message).bytes;

  static List<int> _getSignatureKey(
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
    final canonicalUri = _uriEncodePath('/$key');

    final signed = signRequest(
      method: method,
      canonicalUri: canonicalUri,
      host: host,
      payload: payload,
      accessKey: credentials.accessKey,
      secretKey: credentials.secretKey,
      region: credentials.region,
      utcNow: now,
    );

    final headers = <String, String>{
      'x-amz-date': signed.amzDate,
      'x-amz-content-sha256': signed.payloadHash,
      'Authorization': signed.authorization,
      if (contentType != null) 'Content-Type': contentType,
    };

    // Must be byte-identical to canonicalUri, or the signature won't match.
    final url = Uri.parse('https://$host$canonicalUri');
    final timeout = const Duration(seconds: 30);

    switch (method) {
      case 'PUT':
        return http.put(url, headers: headers, body: payload).timeout(timeout);
      case 'DELETE':
        return http.delete(url, headers: headers).timeout(timeout);
      case 'GET':
        return http.get(url, headers: headers).timeout(timeout);
      default:
        // Previously any unrecognised method silently became a DELETE, which
        // for a storage client is about the worst possible default.
        throw ArgumentError.value(method, 'method', 'Unsupported S3 method');
    }
  }

  /// Builds an AWS Signature Version 4 `Authorization` header.
  ///
  /// Extracted from the request path so it can be checked against AWS's
  /// published test vectors. A hand-rolled signer that has never been compared
  /// with a known-good implementation is the riskiest code in this service —
  /// every failure mode looks like "credentials are wrong".
  @visibleForTesting
  static SignedRequest signRequest({
    required String method,
    required String canonicalUri,
    required String host,
    required Uint8List payload,
    required String accessKey,
    required String secretKey,
    required String region,
    required DateTime utcNow,
    String service = 's3',
    String canonicalQueryString = '',
  }) {
    final amzDate = _formatAmzDate(utcNow);
    final dateStamp = _formatDateStamp(utcNow);
    final payloadHash = sha256.convert(payload).toString();

    final canonicalHeaders =
        'host:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n';
    const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

    final canonicalRequest = '$method\n$canonicalUri\n$canonicalQueryString\n'
        '$canonicalHeaders\n$signedHeaders\n$payloadHash';
    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final hashedCanonicalRequest =
        sha256.convert(utf8.encode(canonicalRequest)).toString();
    final stringToSign =
        'AWS4-HMAC-SHA256\n$amzDate\n$credentialScope\n$hashedCanonicalRequest';

    final signingKey = _getSignatureKey(secretKey, dateStamp, region, service);
    final signature = _hmacSha256(signingKey, utf8.encode(stringToSign))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return SignedRequest(
      authorization: 'AWS4-HMAC-SHA256 '
          'Credential=$accessKey/$credentialScope, '
          'SignedHeaders=$signedHeaders, '
          'Signature=$signature',
      canonicalRequest: canonicalRequest,
      stringToSign: stringToSign,
      signature: signature,
      amzDate: amzDate,
      payloadHash: payloadHash,
    );
  }

  /// Exposed for the signing tests; see [_uriEncodePath].
  @visibleForTesting
  static String encodePathForTest(String path) => _uriEncodePath(path);

  /// Percent-encodes an S3 object path for SigV4.
  ///
  /// AWS requires every byte outside the RFC 3986 unreserved set
  /// (`A-Z a-z 0-9 - _ . ~`) to be encoded with *uppercase* hex, while `/` is
  /// preserved as the path separator. Dart's [Uri.encodeComponent] leaves
  /// `!~*'()` unencoded and so cannot be used here.
  static String _uriEncodePath(String path) {
    const unreserved =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';
    final buffer = StringBuffer();
    for (final byte in utf8.encode(path)) {
      final char = String.fromCharCode(byte);
      if (byte < 128 && (unreserved.contains(char) || char == '/')) {
        buffer.write(char);
      } else {
        buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return buffer.toString();
  }
}

/// The pieces of a signed request, so tests can compare the intermediate
/// strings against AWS's vectors rather than only the final header.
@immutable
class SignedRequest {
  final String authorization;
  final String canonicalRequest;
  final String stringToSign;
  final String signature;
  final String amzDate;
  final String payloadHash;

  const SignedRequest({
    required this.authorization,
    required this.canonicalRequest,
    required this.stringToSign,
    required this.signature,
    required this.amzDate,
    required this.payloadHash,
  });
}

class LatLng {
  final double latitude;
  final double longitude;

  const LatLng({required this.latitude, required this.longitude});
}
