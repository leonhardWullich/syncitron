import 'dart:async';

Future<T> retry<T>(
  Future<T> Function() action, {
  int retries = 3,
  Duration initialDelay = const Duration(milliseconds: 300),
}) async {
  int attempt = 0;
  Duration delay = initialDelay;

  while (true) {
    try {
      return await action();
    } catch (e) {
      if (attempt >= retries) rethrow;
      await Future.delayed(delay);
      delay *= 2;
      attempt++;
    }
  }
}
