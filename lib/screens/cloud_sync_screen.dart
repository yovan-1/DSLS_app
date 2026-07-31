import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/cloud_upload_service.dart';
import '../services/trip_export_service.dart';
import '../services/trip_service.dart';

class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _bucketController =
      TextEditingController(text: AwsCredentials.defaultBucket);
  final _regionController =
      TextEditingController(text: AwsCredentials.defaultRegion);

  bool _isLoading = false;
  bool _isTesting = false;
  bool _isConfigured = false;
  bool _showSecretKey = false;
  bool _needsReentry = false;
  bool _isExporting = false;
  // Was declared mid-class, well after its first use.
  bool _isUploading = false;

  Future<void> _exportTrips() async {
    final tripService = context.read<TripService>();
    final exporter = context.read<TripExportService>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isExporting = true);
    try {
      final shared = await exporter.shareTrips(tripService.trips);
      if (!mounted) return;
      if (!shared) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No trips to export yet')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // Read the service here, not inside the async body: by the time the await
    // resolves the element may be gone.
    final settings = context.read<SettingsService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentSettings(settings);
    });
  }

  Future<void> _loadCurrentSettings(SettingsService settings) async {
    final credentials = await settings.getAwsCredentials();
    if (!mounted) return;

    if (settings.credentialsNeedReentry) {
      // A blob is stored that this build cannot decrypt — an upgrade from a
      // version that derived the key differently. Say so and start clean,
      // rather than showing a configured-looking form that never uploads.
      await settings.clearAwsCredentials();
      if (!mounted) return;
      setState(() {
        _needsReentry = true;
        _isConfigured = false;
      });
      return;
    }

    if (credentials != null && credentials.accessKey.isNotEmpty) {
      setState(() {
        _accessKeyController.text = credentials.accessKey;
        // The secret is deliberately not prefilled. Re-entering it is a small
        // cost; rendering a long-lived IAM secret into a widget that can be
        // revealed, screenshotted or read by an accessibility service is not.
        _bucketController.text = credentials.bucketName;
        _regionController.text = credentials.region;
        _isConfigured = true;
      });
    }
  }

  @override
  void dispose() {
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _bucketController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _saveCredentials() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final settings = context.read<SettingsService>();
      await settings.saveAwsCredentials(AwsCredentials(
        accessKey: _accessKeyController.text.trim(),
        secretKey: _secretKeyController.text.trim(),
        bucketName: _bucketController.text.trim(),
        // Was hardcoded to us-east-1 here, silently overwriting whatever the
        // model carried. A bucket in any other region could never be reached.
        region: _regionController.text.trim().isEmpty
            ? AwsCredentials.defaultRegion
            : _regionController.text.trim(),
      ));

      setState(() {
        _isConfigured = true;
        _needsReentry = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AWS credentials saved securely'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);

    try {
      final cloudService = context.read<CloudUploadService>();
      final success = await cloudService.testConnection();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // Report what S3 actually said. "Check your credentials" was a
            // guess, and usually the wrong one — a missing bucket, a wrong
            // region or a denied policy all look identical under it.
            content: Text(success
                ? 'Connection successful!'
                : cloudService.lastError ?? 'Connection failed.'),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _uploadAllTrips() async {
    final tripService = context.read<TripService>();
    final cloudService = context.read<CloudUploadService>();
    final trips = tripService.trips;

    if (trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No trips to upload')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Trips'),
        content: Text('Upload ${trips.length} trips to AWS S3?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isUploading = true);

    try {
      int uploaded = 0;

      for (final trip in trips) {
        final success = await cloudService.uploadTrip(trip);
        if (success) uploaded++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploaded $uploaded/${trips.length} trips'),
            backgroundColor: uploaded == trips.length ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Sync'),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // Watching the upload service too, so its notifyListeners actually
      // reaches the UI — previously the screen consumed only SettingsService
      // and every notification the upload service fired went nowhere.
      body: Consumer2<SettingsService, CloudUploadService>(
        builder: (context, settings, uploads, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStatusCard(settings),
              const SizedBox(height: 20),
              _buildQueueCard(uploads),
              _buildCredentialsForm(),
              const SizedBox(height: 20),
              _buildActionsCard(),
              const SizedBox(height: 20),
              _buildAutoUploadCard(settings),
              const SizedBox(height: 20),
              _buildInfoCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(SettingsService settings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isConfigured ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isConfigured ? Colors.green : Colors.orange,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isConfigured ? Icons.cloud_done : Icons.cloud_off,
            color: _isConfigured ? Colors.green : Colors.orange,
            size: 40,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isConfigured ? 'AWS Configured' : 'Not Configured',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _isConfigured ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                ),
                Text(
                  _isConfigured
                      ? 'Trip data can be uploaded to S3'
                      : 'Configure AWS credentials to enable cloud sync',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isConfigured ? Colors.green.shade600 : Colors.orange.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What the queue is actually doing.
  ///
  /// The screen used to keep its own `_isUploading`/`_isTesting` and read none
  /// of the service's state, so `pendingCount`, `lastError` and the upload
  /// history existed but were never shown — and a real S3 error was replaced
  /// with "Connection failed. Check your credentials."
  Widget _buildQueueCard(CloudUploadService uploads) {
    final pending = uploads.pendingCount;
    final error = uploads.lastError;
    final history = uploads.uploadHistory;

    if (pending == 0 && error == null && history.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.sync, size: 20),
                SizedBox(width: 8),
                Text(
                  'Upload Queue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  pending == 0 ? Icons.check_circle_outline : Icons.schedule,
                  size: 18,
                  color: pending == 0 ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  pending == 0
                      ? 'Nothing waiting to upload'
                      : '$pending trip${pending == 1 ? '' : 's'} waiting — '
                          'will retry automatically',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  // The real reason, not a guess about credentials.
                  'Last error: $error',
                  style: TextStyle(fontSize: 11, color: Colors.red.shade900),
                ),
              ),
            ],
            if (history.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Recent attempts',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 6),
              ...history.take(5).map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            entry.succeeded ? Icons.check : Icons.close,
                            size: 14,
                            color: entry.succeeded ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${_formatTime(entry.at)}  ${entry.tripId}',
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
  }

  Widget _buildCredentialsForm() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.key, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'AWS Credentials',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Credentials are encrypted locally using AES-256',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              // Encryption at rest does not change the fact that the device
              // holds a durable key to the bucket. Say so where it matters.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_outlined,
                        size: 18, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This device stores a long-lived AWS key. Anyone with '
                        'the unlocked phone can use it. Scope the IAM policy to '
                        'PutObject on this bucket only, and rotate the key if '
                        'the device is lost.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              if (_needsReentry) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your saved credentials could not be read after the '
                          'app update and have been cleared. Please enter them '
                          'again.',
                          style: TextStyle(
                              fontSize: 11, color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _accessKeyController,
                decoration: const InputDecoration(
                  labelText: 'Access Key ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Access Key is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _secretKeyController,
                obscureText: !_showSecretKey,
                decoration: InputDecoration(
                  labelText: 'Secret Access Key',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_showSecretKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showSecretKey = !_showSecretKey),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Secret Key is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _regionController,
                decoration: const InputDecoration(
                  labelText: 'AWS Region',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.public),
                  hintText: AwsCredentials.defaultRegion,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Region is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bucketController,
                decoration: const InputDecoration(
                  labelText: 'S3 Bucket Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.storage),
                  hintText: AwsCredentials.defaultBucket,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Bucket name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveCredentials,
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save Credentials'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _isTesting ? null : _testConnection,
                    child: _isTesting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Test'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    final tripService = context.read<TripService>();
    final tripCount = tripService.trips.length;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_upload, size: 20),
                SizedBox(width: 8),
                Text(
                  'Cloud Actions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.directions_car, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                Text('$tripCount trips available for upload'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (!_isConfigured || _isUploading) ? null : _uploadAllTrips,
                icon: _isUploading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload),
                label: Text(_isUploading ? 'Uploading...' : 'Upload All Trips'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                // Needs no AWS account at all — the useful path for a pilot
                // device that was never given credentials.
                onPressed: (tripCount == 0 || _isExporting) ? null : _exportTrips,
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(_isExporting ? 'Preparing...' : 'Export & Share'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Export writes a JSON and a CSV and hands them to the share '
              'sheet. No AWS account needed.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoUploadCard(SettingsService settings) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.schedule, size: 20),
                SizedBox(width: 8),
                Text(
                  'Auto Upload',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Automatically upload trips when they end',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Auto Upload'),
              subtitle: Text(
                settings.autoUploadEnabled
                    ? 'Trips will be uploaded automatically'
                    : 'Manual upload required',
              ),
              value: settings.autoUploadEnabled,
              onChanged: (value) => settings.setAutoUpload(value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'For Road Department',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Uploaded trip data includes:\n'
            '• Speed limit and actual speeds\n'
            '• GPS route path, sampled once a second\n'
            '• Road surface estimates, where OpenStreetMap has them\n'
            '• Risk analysis scores\n\n'
            'Trips recorded before this version have no route path.\n\n'
            'This data helps the roads department:\n'
            '• Identify high-risk road segments\n'
            '• Adjust speed limits based on conditions\n'
            '• Plan infrastructure improvements',
            style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
          ),
        ],
      ),
    );
  }
}
