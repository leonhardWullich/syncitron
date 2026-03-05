import 'dart:async';

import '../core/logger.dart';

/// Retry a future with exponential backoff.
///
/// Automatically retries the action up to [retries] times with
/// exponential backoff between attempts.
///
/// The delay grows exponentially: initialDelay, initialDelay * 2, etc.,
/// but never exceeds [maxDelay].
///
/// ```dart
/// await retry(
///   () => remoteAdapter.sync(),
///   retries: 3,
///   initialDelay: Duration(milliseconds: 500),
///   maxDelay: Duration(seconds: 30),
/// );
/// ```
Future<T> retry<T>(
  Future<T> Function() action, {
  int retries = 3,
  Duration initialDelay = const Duration(milliseconds: 300),
  Duration maxDelay = const Duration(seconds: 30),
  Logger? logger,
}) async {
  int attempt = 0;
  Duration delay = initialDelay;

  while (true) {
    try {
      return await action();
    } catch (e) {
      attempt++;
      if (attempt > retries) {
        logger?.error('Retry limit exceeded after $attempt attempts', error: e);
        rethrow;
      }

      logger?.warning(
        'Attempt $attempt failed, retrying in ${delay.inMilliseconds}ms',
        error: e,
      );

      await Future.delayed(delay);
      // Exponential backoff with cap
      delay = Duration(
        milliseconds: (delay.inMilliseconds * 2).clamp(
          0,
          maxDelay.inMilliseconds,
        ),
      );
    }
  }
}
