import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(dynamic error, StackTrace stackTrace)? errorBuilder;
  final VoidCallback? onRetry;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
    this.onRetry,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  dynamic _error;
  StackTrace? _stackTrace;
  bool _hasError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorWidget();
    }

    return widget.child;
  }

  Widget _buildErrorWidget() {
    if (widget.errorBuilder != null) {
      return widget.errorBuilder!(_error, _stackTrace!);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _getErrorMessage(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (widget.onRetry != null)
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _error = null;
                    _stackTrace = null;
                  });
                  widget.onRetry?.call();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                if (kDebugMode) {
                  debugPrint('Error: $_error');
                  debugPrintStack(stackTrace: _stackTrace);
                }
              },
              child: const Text('View Details'),
            ),
          ],
        ),
      ),
    );
  }

  String _getErrorMessage() {
    if (_error == null) return 'An unexpected error occurred';

    final errorString = _error.toString();
    if (errorString.contains('SocketException') ||
        errorString.contains('Network is unreachable')) {
      return 'Network connection error. Please check your internet connection.';
    }
    if (errorString.contains('Location')) {
      return 'Unable to get location. Please enable GPS permissions.';
    }
    if (errorString.contains('Camera')) {
      return 'Camera access error. Please check camera permissions.';
    }
    if (errorString.contains('Permission')) {
      return 'Permission denied. Please grant required permissions in settings.';
    }

    return 'An unexpected error occurred. Please try again.';
  }
}

class ErrorBoundaryWrapper extends StatelessWidget {
  final Widget child;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorBoundaryWrapper({
    super.key,
    required this.child,
    this.title = 'Something went wrong',
    this.message = 'An unexpected error occurred',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      errorBuilder: (error, stackTrace) {
        return _ErrorDisplay(
          title: title,
          message: message,
          onRetry: onRetry,
        );
      },
      onRetry: onRetry,
      child: child,
    );
  }
}

class _ErrorDisplay extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _ErrorDisplay({
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red[700],
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.red[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}