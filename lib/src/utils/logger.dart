import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum LogLevel { none, error, warn, info, debug }

/// Logger interface
abstract class Logger {
  set level(LogLevel level);
  void debug(String message);
  void info(String message);
  void warn(String message);
  void error(String message);

  void startTimer();
  void stopTimer();
}

/// Default logger that prints to stdout
class PrintLogger implements Logger {
  LogLevel _level = LogLevel.debug;
  DateTime? _time;
  bool _isTiming = false;

  void output(LogLevel level, String message, [bool showTrace = false]) {
    if (_level.index >= level.index) {
      String time = _isTiming
          ? ' (took ${DateTime.now().difference(_time!).inMicroseconds}µs)'
          : '';
      String trace = showTrace ? '\n${StackTrace.current}' : '';
      print('${level.name}: $message$time$trace');
    }
  }

  @override
  set level(LogLevel level) => _level = level;

  @override
  void debug(String message) {
    output(LogLevel.debug, message);
  }

  @override
  void info(String message) {
    output(LogLevel.info, message);
  }

  @override
  void warn(String message) {
    output(LogLevel.warn, message);
  }

  @override
  void error(String message) {
    output(LogLevel.error, message);
  }

  @override
  void startTimer() {
    _time = DateTime.now();
    _isTiming = true;
  }

  @override
  void stopTimer() {
    _isTiming = false;
  }
}

/// Default logger that prints to stdout as JSON with extra details
class PrintJsonLogger extends PrintLogger {
  @override
  void output(LogLevel level, String message, [bool trace = false]) {
    if (_level.index >= level.index) {
      print(json.encode(format(message, trace)));
    }
  }

  dynamic format(String message, bool trace) {
    dynamic data = {
      'level': _level.toString().split('.').last,
      'time': DateTime.now().toIso8601String(),
      'message': message,
    };
    if (trace) {
      data['trace'] = StackTrace.current.toString();
    }
    if (_isTiming) {
      data['timing'] = {
        'started': _time!.toIso8601String(),
        'now': DateTime.now().toIso8601String(),
        'elapsed': DateTime.now().difference(_time!).inMicroseconds,
      };
    }
    return data;
  }

  @override
  void error(String message) {
    output(LogLevel.error, message, true);
  }
}

/// Logger that writes to a file
/// TODO: May lock file if crash occurs while sink is open. Do we need to
/// open and close the sink for every write?
class FileLogger extends PrintJsonLogger {
  IOSink? _sink;

  FutureOr<void> init(String id) async {
    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (e) {
      return;
    }

    // Open a file stream for writing
    final file = File('${dir.path}/$id.log.json');
    _sink = file.openWrite(mode: FileMode.writeOnly);
  }

  void _write(dynamic data) {
    _sink?.write(json.encode(data));
  }

  void dispose() {
    _sink?.close();
    _sink = null;
  }

  @override
  void output(LogLevel level, String message, [bool trace = false]) {
    if (_level.index >= level.index) {
      _write(format(message, trace));
    }
  }
}
