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
}

/// Default logger that prints to stdout
class PrintLogger implements Logger {
  LogLevel _level = LogLevel.debug;

  @override
  set level(LogLevel level) => _level = level;

  @override
  void debug(String message) {
    if (_level.index >= LogLevel.debug.index) {
      print('DEBUG: $message');
    }
  }

  @override
  void info(String message) {
    if (_level.index >= LogLevel.info.index) {
      print('INFO: $message');
    }
  }

  @override
  void warn(String message) {
    if (_level.index >= LogLevel.warn.index) {
      print('WARN: $message');
    }
  }

  @override
  void error(String message) {
    if (_level.index >= LogLevel.error.index) {
      print('ERROR: $message\n${StackTrace.current}');
    }
  }
}

/// Default logger that prints to stdout as JSON with extra details
class PrintJsonLogger implements Logger {
  LogLevel _level = LogLevel.debug;

  @override
  set level(LogLevel level) => _level = level;

  String _format(LogLevel level, String message, [bool trace = false]) {
    return '{ "level": "${level.toString().split('.').last}", "time": "${DateTime.now().toIso8601String()}", "message": "$message"${trace ? ', "trace": "${StackTrace.current}"}' : ''}';
  }

  @override
  void debug(String message) {
    if (_level.index >= LogLevel.debug.index) {
      print(_format(LogLevel.debug, message));
    }
  }

  @override
  void info(String message) {
    if (_level.index >= LogLevel.info.index) {
      print(_format(LogLevel.info, message));
    }
  }

  @override
  void warn(String message) {
    if (_level.index >= LogLevel.warn.index) {
      print(_format(LogLevel.warn, message));
    }
  }

  @override
  void error(String message) {
    if (_level.index >= LogLevel.error.index) {
      print(_format(LogLevel.error, message, true));
    }
  }
}

class FileLogger implements Logger {
  IOSink? _sink;
  LogLevel _level = LogLevel.debug;

  @override
  set level(LogLevel level) => _level = level;

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

  dynamic _format(LogLevel level, String message, [bool trace = false]) {
    dynamic data = {
      'level': level.toString().split('.').last,
      'time': DateTime.now().toIso8601String(),
      'message': message,
    };
    if (trace) {
      data['trace'] = StackTrace.current.toString();
    }
    return data;
  }

  @override
  void debug(String message) {
    if (_level.index >= LogLevel.debug.index) {
      _write(_format(LogLevel.debug, message));
    }
  }

  @override
  void info(String message) {
    if (_level.index >= LogLevel.info.index) {
      _write(_format(LogLevel.info, message));
    }
  }

  @override
  void warn(String message) {
    if (_level.index >= LogLevel.warn.index) {
      _write(_format(LogLevel.warn, message));
    }
  }

  @override
  void error(String message) {
    if (_level.index >= LogLevel.error.index) {
      _write(_format(LogLevel.error, message, true));
    }
  }
}
