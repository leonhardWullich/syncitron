import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:replicore/replicore.dart';

/// Wraps [SyncEngine] with:
///   - an initial sync on startup
///   - connectivity-triggered sync (fires immediately on reconnect)
///   - periodic background sync (every 60 s)
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

  /// Latest status message forwarded from [SyncEngine.statusStream].
  final syncStatus = ValueNotifier<String>('');

  /// Non-null when the last sync ended with an error.
  /// Cleared automatically at the start of each new sync run.
  final syncError = ValueNotifier<ReplicoreException?>(null);

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

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        debugPrint('[SyncService] Reconnected — triggering sync.');
        sync();
      }
    });

    _periodicTimer = Timer.periodic(const Duration(seconds: 60), (_) => sync());

    sync(); // immediate sync on startup
  }

  void dispose() {
    _statusSub?.cancel();
    _connectivitySub?.cancel();
    _periodicTimer?.cancel();
    _engine.dispose();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Triggers a full sync. Safe to call from a Pull-to-Refresh handler.
  ///
  /// Errors are written to [syncError] — not thrown — so UI widgets can
  /// react without wrapping every call-site in try/catch.
  Future<void> sync() async {
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
      debugPrint('[SyncService] Network error (offline=${e.isOffline}): $e');
    } on SchemaMigrationException catch (e) {
      // Developer mistake → crash loudly in debug, log in release.
      syncError.value = e;
      debugPrint('[SyncService] ‼️ Schema error on table "${e.table}": $e');
      if (kDebugMode) rethrow;
    } on ReplicoreException catch (e) {
      syncError.value = e;
      debugPrint('[SyncService] Sync error: $e');
    }
  }
}
