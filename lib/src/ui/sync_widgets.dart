import 'package:flutter/material.dart';
import 'package:replicore/replicore.dart';

/// Displays the current sync status with customizable UI.
///
/// Example:
/// ```dart
/// SyncStatusWidget(
///   statusStream: engine.statusStream,
///   onSync: () => SyncService.instance.sync(),
/// )
/// ```
class SyncStatusWidget extends StatelessWidget {
  /// Stream of status messages from the sync engine.
  final Stream<String> statusStream;

  /// Callback when user taps the sync button.
  final VoidCallback onSync;

  /// Custom builder for the sync status UI.
  ///
  /// If provided, overrides the default UI.
  final Widget Function(BuildContext context, String status)? builder;

  /// Show a circular progress indicator while syncing.
  final bool showProgress;

  /// Text color for status messages.
  final Color? textColor;

  const SyncStatusWidget({
    super.key,
    required this.statusStream,
    required this.onSync,
    this.builder,
    this.showProgress = true,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: statusStream,
      initialData: 'Ready',
      builder: (context, snapshot) {
        final status = snapshot.data ?? '';

        if (builder != null) {
          return builder!(context, status);
        }

        final isSyncing =
            !status.contains('completed') &&
            !status.contains('Ready') &&
            status.isNotEmpty;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSyncing && showProgress)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.sync),
                onPressed: onSync,
                tooltip: 'Manually sync',
              ),
            if (status.isNotEmpty)
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(color: textColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Displays sync metrics (pulled, pushed, duration) in a card format.
///
/// Example:
/// ```dart
/// SyncMetricsCard(
///   metrics: lastSessionMetrics,
/// )
/// ```
class SyncMetricsCard extends StatelessWidget {
  /// Session metrics to display.
  final SyncSessionMetrics metrics;

  /// Card elevation/shadow.
  final double elevation;

  /// Background color.
  final Color? backgroundColor;

  /// Whether to show the card or return SizedBox.shrink() if no metrics.
  final bool showWhenEmpty;

  const SyncMetricsCard({
    super.key,
    required this.metrics,
    this.elevation = 1,
    this.backgroundColor,
    this.showWhenEmpty = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showWhenEmpty &&
        metrics.totalRecordsPulled == 0 &&
        metrics.totalRecordsPushed == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: elevation,
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sync Metrics',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _MetricsRow(
              label: 'Pulled',
              value: metrics.totalRecordsPulled.toString(),
            ),
            _MetricsRow(
              label: 'Pushed',
              value: metrics.totalRecordsPushed.toString(),
            ),
            _MetricsRow(
              label: 'Duration',
              value: '${metrics.totalDuration.inMilliseconds}ms',
            ),
            if (metrics.totalErrors > 0) ...[
              const SizedBox(height: 8),
              _MetricsRow(
                label: 'Errors',
                value: metrics.totalErrors.toString(),
                valueColor: Colors.red,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetricsRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
        ),
      ],
    );
  }
}

/// Displays an error banner for sync exceptions.
///
/// Automatically styles the banner based on error type.
///
/// Example:
/// ```dart
/// SyncErrorBanner(
///   error: syncError,
///   onRetry: () => SyncService.instance.sync(),
///   onDismiss: () => clearError(),
/// )
/// ```
class SyncErrorBanner extends StatelessWidget {
  /// The sync error to display (null hides the banner).
  final ReplicoreException? error;

  /// Callback when user taps Retry button.
  final VoidCallback? onRetry;

  /// Callback when user dismisses the banner.
  final VoidCallback? onDismiss;

  /// Custom error message instead of default categorization.
  final String? customMessage;

  const SyncErrorBanner({
    super.key,
    required this.error,
    this.onRetry,
    this.onDismiss,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const SizedBox.shrink();
    }

    final (icon, message, bgColor) = _categorizeError(context);

    return MaterialBanner(
      backgroundColor: bgColor,
      leading: Icon(icon),
      content: Text(customMessage ?? message),
      actions: [
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        if (onDismiss != null)
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
      ],
    );
  }

  (IconData, String, Color) _categorizeError(BuildContext context) {
    return switch (error!) {
      SyncNetworkException(:final isOffline) =>
        isOffline
            ? (
                Icons.wifi_off,
                'You\'re offline. Changes saved locally.',
                Colors.orange.withOpacity(0.1),
              )
            : (
                Icons.cloud_off,
                'Server unreachable. Retrying automatically.',
                Colors.orange.withOpacity(0.1),
              ),
      SyncAuthException() => (
        Icons.lock_outline,
        'Session expired. Please log in again.',
        Theme.of(context).colorScheme.errorContainer,
      ),
      SchemaMigrationException() => (
        Icons.warning,
        'Schema mismatch. Please update the app.',
        Theme.of(context).colorScheme.errorContainer,
      ),
      _ => (
        Icons.sync_problem,
        'Sync error: ${error!.message}',
        Theme.of(context).colorScheme.errorContainer,
      ),
    };
  }
}

/// Indicator showing whether the device is online or offline.
///
/// Example:
/// ```dart
/// OfflineIndicator(
///   isOnline: connectivity.isOnline,
/// )
/// ```
class OfflineIndicator extends StatelessWidget {
  /// Whether the device is connected to the network.
  final bool isOnline;

  /// Icon to show when offline.
  final IconData offlineIcon;

  /// Icon to show when online.
  final IconData onlineIcon;

  /// Label to show when offline.
  final String offlineLabel;

  /// Custom builder for the indicator.
  final Widget Function(BuildContext, bool isOnline)? builder;

  const OfflineIndicator({
    super.key,
    required this.isOnline,
    this.offlineIcon = Icons.cloud_off,
    this.onlineIcon = Icons.cloud_done,
    this.offlineLabel = 'Offline',
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    if (builder != null) {
      return builder!(context, isOnline);
    }

    return Visibility(
      visible: !isOnline,
      child: Chip(
        avatar: Icon(offlineIcon, size: 18),
        label: Text(offlineLabel),
      ),
    );
  }
}

/// A button that triggers sync and shows loading state.
///
/// Example:
/// ```dart
/// SyncButton(
///   onPressed: () => SyncService.instance.sync(),
///   isSyncing: syncService.isSyncing,
/// )
/// ```
class SyncButton extends StatelessWidget {
  /// Callback when button is pressed.
  final VoidCallback onPressed;

  /// Whether sync is currently in progress.
  final bool isSyncing;

  /// Button label.
  final String label;

  /// Icon to show when not syncing.
  final IconData icon;

  /// Icon to show when syncing.
  final IconData? loadingIcon;

  /// Custom loading indicator instead of default spinner.
  final Widget? customLoadingIndicator;

  const SyncButton({
    super.key,
    required this.onPressed,
    required this.isSyncing,
    this.label = 'Sync',
    this.icon = Icons.sync,
    this.loadingIcon,
    this.customLoadingIndicator,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isSyncing ? null : onPressed,
      icon: isSyncing
          ? (customLoadingIndicator ??
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ))
          : Icon(icon),
      label: Text(label),
    );
  }
}

/// Comprehensive sync status panel with metrics, errors, and controls.
///
/// Combines status, metrics, error display, and sync button into one widget.
///
/// Example:
/// ```dart
/// SyncStatusPanel(
///   statusStream: engine.statusStream,
///   metrics: lastMetrics,
///   error: lastError,
///   onSync: () => SyncService.instance.sync(),
/// )
/// ```
class SyncStatusPanel extends StatelessWidget {
  /// Stream of status messages.
  final Stream<String> statusStream;

  /// Last session metrics.
  final SyncSessionMetrics? metrics;

  /// Current error (if any).
  final ReplicoreException? error;

  /// Callback for manual sync.
  final VoidCallback onSync;

  /// Callback to dismiss error.
  final VoidCallback? onErrorDismiss;

  /// Whether to show metrics card.
  final bool showMetrics;

  /// Whether to show sync button.
  final bool showButton;

  /// Whether to show status stream.
  final bool showStatus;

  const SyncStatusPanel({
    super.key,
    required this.statusStream,
    required this.onSync,
    this.metrics,
    this.error,
    this.onErrorDismiss,
    this.showMetrics = true,
    this.showButton = true,
    this.showStatus = true,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            SyncErrorBanner(
              error: error,
              onRetry: onSync,
              onDismiss: onErrorDismiss,
            ),
          if (showStatus) ...[
            const SizedBox(height: 8),
            SyncStatusWidget(statusStream: statusStream, onSync: onSync),
          ],
          if (showMetrics && metrics != null) ...[
            const SizedBox(height: 16),
            SyncMetricsCard(metrics: metrics!),
          ],
          if (showButton) ...[
            const SizedBox(height: 16),
            StreamBuilder<String>(
              stream: statusStream,
              initialData: 'Ready',
              builder: (context, snapshot) {
                final status = snapshot.data ?? '';
                final isSyncing =
                    !status.contains('completed') &&
                    !status.contains('Ready') &&
                    status.isNotEmpty;

                return SyncButton(onPressed: onSync, isSyncing: isSyncing);
              },
            ),
          ],
        ],
      ),
    );
  }
}
