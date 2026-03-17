import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:syncitron/syncitron.dart';

import '../main.dart'; // for appRealtimeManager access

/// Wraps [SyncEngine] with:
///   - an initial sync on startup
///   - connectivity-triggered sync (fires immediately on reconnect)
///   - periodic background sync (every 30 s when online)
///   - periodic connectivity poll as fallback (stream is unreliable on Simulator)
///   - typed error handling surfaced as [ValueNotifier]s
///
/// Usage in the UI:
/// ```dart
/// ValueListenableBuilder(
///   valueListenable: SyncService.instance.syncError,
///   builder: (context, error, _) {
///     if (error is SyncNetworkException && error.isOffline) {
///       return const OfflineBanner();
///     }
///     return const SizedBox.shrink();
///   },
/// )
/// ```
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  late SyncEngine _engine;

  /// Single retained instance — creating new Connectivity() instances
  /// can cause the stream to miss events on some platforms.
  final _connectivity = Connectivity();

  /// Whether the device was offline on the last check.
  /// Used to detect offline → online transitions.
  bool _wasOffline = false;

  /// Prevents overlapping sync runs.
  bool _syncInProgress = false;

  /// Latest status message forwarded from [SyncEngine.statusStream].
  final syncStatus = ValueNotifier<String>('');

  /// Non-null when the last sync ended with an error.
  /// Cleared automatically at the start of each new sync run.
  final syncError = ValueNotifier<syncitronException?>(null);

  /// Current connectivity state — UI can show an offline banner.
  final isOnline = ValueNotifier<bool>(true);

  StreamSubscription<String>? _statusSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Call once after [SyncEngine.init] completes — typically in [main].
  void start({required SyncEngine engine}) {
    _engine = engine;

    _statusSub = _engine.statusStream.listen((msg) {
      syncStatus.value = msg;
    });

    // Listen for connectivity changes (retained instance).
    _connectivitySub =
        _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);

    // Periodic fallback: the stream doesn't always fire on iOS Simulator.
    // Polls connectivity every 30 s and syncs if online.
    _periodicTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _periodicCheck(),
    );

    sync(); // immediate sync on startup
  }

  void dispose() {
    _statusSub?.cancel();
    _connectivitySub?.cancel();
    _periodicTimer?.cancel();
    _engine.dispose();

    // Close real-time subscriptions if active
    if (appRealtimeManager != null) {
      appRealtimeManager!.close();
    }
  }

  // ── Connectivity handling ──────────────────────────────────────────────────

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    isOnline.value = online;

    debugPrint(
      '[SyncService] Connectivity stream: $results '
      '(online=$online, wasOffline=$_wasOffline)',
    );

    if (online && _wasOffline) {
      _wasOffline = false;
      debugPrint('[SyncService] Reconnected — triggering sync.');
      sync();
    } else if (!online) {
      _wasOffline = true;
      debugPrint('[SyncService] Device went offline.');
    }
  }

  /// Fallback poll — checks connectivity and syncs if appropriate.
  Future<void> _periodicCheck() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final online = results.any((r) => r != ConnectivityResult.none);
      isOnline.value = online;

      if (online && _wasOffline) {
        _wasOffline = false;
        debugPrint('[SyncService] Periodic poll: back online — syncing.');
        await sync();
      } else if (!online) {
        _wasOffline = true;
      } else if (online) {
        // Regular periodic sync while online
        await sync();
      }
    } catch (e) {
      debugPrint('[SyncService] Periodic connectivity check failed: $e');
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Triggers a full sync. Safe to call from a Pull-to-Refresh handler.
  ///
  /// Errors are written to [syncError] — not thrown — so UI widgets can
  /// react without wrapping every call-site in try/catch.
  ///
  /// Re-entrant: if a sync is already running, this call is silently skipped.
  Future<void> sync() async {
    if (_syncInProgress) {
      debugPrint('[SyncService] Sync already in progress — skipping.');
      return;
    }
    _syncInProgress = true;
    syncError.value = null;

    try {
      await _engine.syncAll();
    } on SyncAuthException catch (e) {
      // Session expired → the UI should redirect to the login screen.
      syncError.value = e;
      debugPrint('[SyncService] Auth error: $e');
    } on SyncNetworkException catch (e) {
      // Offline or server unreachable → show a non-blocking banner.
      syncError.value = e;
      _wasOffline = true;
      debugPrint('[SyncService] Network error (offline=${e.isOffline}): $e');
    } on SchemaMigrationException catch (e) {
      // Developer mistake → crash loudly in debug, log in release.
      syncError.value = e;
      debugPrint('[SyncService] ‼️ Schema error on table "${e.table}": $e');
      if (kDebugMode) rethrow;
    } on syncitronException catch (e) {
      syncError.value = e;
      debugPrint('[SyncService] Sync error: $e');
    } finally {
      _syncInProgress = false;
    }
  }
}
