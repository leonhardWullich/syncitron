/// Severity levels for log messages.
enum LogLevel {
  debug(0),
  info(1),
  warning(2),
  error(3),
  critical(4);

  final int severity;
  const LogLevel(this.severity);

  bool isAtLeast(LogLevel other) => severity >= other.severity;
}

/// Represents a structured log entry for enterprise applications.
class LogEntry {
  final LogLevel level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  final Map<String, dynamic>? context;

  LogEntry({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.context,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  /// Convert to JSON for structured logging systems (ELK, Datadog, etc.)
  Map<String, dynamic> toJson() => {
    'level': level.name,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'error': error?.toString(),
    'stack_trace': stackTrace?.toString(),
    'context': context,
  };

  @override
  String toString() {
    final levelStr = level.name.toUpperCase().padRight(8);
    final msg = '[$levelStr] $message';
    if (error != null) {
      return '$msg\nError: $error';
    }
    return msg;
  }
}

/// Abstract logger interface for dependency injection.
abstract class Logger {
  void debug(String message, {Map<String, dynamic>? context});
  void info(String message, {Map<String, dynamic>? context});
  void warning(
    String message, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  });
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  });
  void critical(String message, {Object? error, StackTrace? stackTrace});
  void log(LogEntry entry);
}

/// Default console logger implementation.
class ConsoleLogger implements Logger {
  final LogLevel minLevel;

  ConsoleLogger({this.minLevel = LogLevel.debug});

  @override
  void debug(String message, {Map<String, dynamic>? context}) {
    _logIfLevel(
      LogEntry(level: LogLevel.debug, message: message, context: context),
    );
  }

  @override
  void info(String message, {Map<String, dynamic>? context}) {
    _logIfLevel(
      LogEntry(level: LogLevel.info, message: message, context: context),
    );
  }

  @override
  void warning(
    String message, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logIfLevel(
      LogEntry(
        level: LogLevel.warning,
        message: message,
        context: context,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    _logIfLevel(
      LogEntry(
        level: LogLevel.error,
        message: message,
        context: context,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  void critical(String message, {Object? error, StackTrace? stackTrace}) {
    _logIfLevel(
      LogEntry(
        level: LogLevel.critical,
        message: message,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  void log(LogEntry entry) {
    _logIfLevel(entry);
  }

  void _logIfLevel(LogEntry entry) {
    if (entry.level.isAtLeast(minLevel)) {
      print(entry.toString());
      if (entry.context != null) {
        print('  Context: ${entry.context}');
      }
    }
  }
}

/// No-op logger for production (disable logging).
class NoOpLogger implements Logger {
  const NoOpLogger();

  @override
  void debug(String message, {Map<String, dynamic>? context}) {}

  @override
  void info(String message, {Map<String, dynamic>? context}) {}

  @override
  void warning(
    String message, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {}

  @override
  void critical(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void log(LogEntry entry) {}
}

/// Aggregates multiple loggers (useful for multi-channel logging).
class MultiLogger implements Logger {
  final List<Logger> loggers;

  MultiLogger(this.loggers);

  @override
  void debug(String message, {Map<String, dynamic>? context}) {
    for (var logger in loggers) {
      logger.debug(message, context: context);
    }
  }

  @override
  void info(String message, {Map<String, dynamic>? context}) {
    for (var logger in loggers) {
      logger.info(message, context: context);
    }
  }

  @override
  void warning(
    String message, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    for (var logger in loggers) {
      logger.warning(
        message,
        context: context,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    for (var logger in loggers) {
      logger.error(
        message,
        error: error,
        stackTrace: stackTrace,
        context: context,
      );
    }
  }

  @override
  void critical(String message, {Object? error, StackTrace? stackTrace}) {
    for (var logger in loggers) {
      logger.critical(message, error: error, stackTrace: stackTrace);
    }
  }

  @override
  void log(LogEntry entry) {
    for (var logger in loggers) {
      logger.log(entry);
    }
  }
}
