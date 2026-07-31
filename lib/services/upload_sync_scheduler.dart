import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'cloud_upload_service.dart';

/// Drains the upload queue when there is a network to drain it over.
///
/// Kept separate from [CloudUploadService] so the queue logic stays a pure,
/// testable thing and only this class touches the connectivity plugin.
///
/// Before this, nothing ever retried: a trip whose upload failed was dropped on
/// the floor, and the "pending" concept existed only as an in-memory list that
/// nothing wrote to and that emptied on every restart.
class UploadSyncScheduler {
  final CloudUploadService _uploads;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _hadNetwork = true;

  UploadSyncScheduler({
    required CloudUploadService uploads,
    Connectivity? connectivity,
  })  : _uploads = uploads,
        _connectivity = connectivity ?? Connectivity();

  /// Drains once for anything left over from a previous run, then watches for
  /// the network coming back.
  Future<void> start() async {
    unawaited(_drain('startup'));

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final hasNetwork = _hasNetwork(results);
      // Only on the rising edge. Android emits changes freely, and a drain per
      // event would hammer S3 while the radio settles.
      if (hasNetwork && !_hadNetwork) {
        unawaited(_drain('network regained'));
      }
      _hadNetwork = hasNetwork;
    });

    _hadNetwork = _hasNetwork(await _connectivity.checkConnectivity());
  }

  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<void> _drain(String reason) async {
    try {
      final uploaded = await _uploads.syncPendingUploads();
      if (uploaded > 0) {
        debugPrint('[UploadSync] Uploaded $uploaded queued trips ($reason)');
      }
    } catch (e) {
      debugPrint('[UploadSync] Drain failed ($reason): $e');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
