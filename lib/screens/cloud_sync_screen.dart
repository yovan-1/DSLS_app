import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/cloud_upload_service.dart';
import '../services/trip_service.dart';

class CloudSyncScreen extends StatefulWidget {
  final Function(int)? onBack;

  const CloudSyncScreen({super.key, this.onBack});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _bucketController = TextEditingController(text: 'dsls-trip-data');
  
  bool _isLoading = false;
  bool _isTesting = false;
  bool _isConfigured = false;
  bool _showSecretKey = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final settings = context.read<SettingsService>();
    final credentials = await settings.getAwsCredentials();
    if (credentials != null && credentials.accessKey.isNotEmpty) {
      setState(() {
        _accessKeyController.text = credentials.accessKey;
        _secretKeyController.text = credentials.secretKey;
        _bucketController.text = credentials.bucketName;
        _isConfigured = true;
      });
    }
  }

  @override
  void dispose() {
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _bucketController.dispose();
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
        region: 'us-east-1',
      ));

      setState(() => _isConfigured = true);

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
      final settings = context.read<SettingsService>();
      final cloudService = CloudUploadService(settingsService: settings);
      final success = await cloudService.testConnection();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
                ? 'Connection successful!' 
                : 'Connection failed. Check your credentials.'),
            backgroundColor: success ? Colors.green : Colors.red,
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
      final settings = context.read<SettingsService>();
      final cloudService = CloudUploadService(settingsService: settings);
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

  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Sync'),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => widget.onBack?.call(0),
        ),
      ),
      body: Consumer<SettingsService>(
        builder: (context, settings, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStatusCard(settings),
              const SizedBox(height: 20),
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
                controller: _bucketController,
                decoration: const InputDecoration(
                  labelText: 'S3 Bucket Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.storage),
                  hintText: 'dsls-trip-data',
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
            '• GPS route path\n'
            '• Road surface estimates\n'
            '• Risk analysis scores\n\n'
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
