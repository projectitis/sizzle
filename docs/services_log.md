# Logging

[:arrow_left: Back to services](services.md)

The `Services` class exposes a logger that can be used to log errors, debug
messages and other log data. By default the `PrintLogger` is used, but the
logger can be changed just by creating and assigning a new one.

```dart
Services.log
```

To log a message, call one of `debug`, `info`, `warn` or `error`:

```dart
Services.log.info('Game is starting up');
Services.log.warn('Sprite not found. Using fallback');
Services.log.error('Could not load save file');
```


## Filtering by level

Each logger exposes a
[`level`](../lib/src/utils/logger.dart#:~:text=set+level) setter which filters
out any messages below the given
[`LogLevel`](../lib/src/utils/logger.dart#:~:text=LogLevel). Levels are, in
order, `none`, `error`, `warn`, `info`, `debug`. Messages logged at or below
the configured level are emitted; everything above is dropped.

```dart
Services.log.level = LogLevel.warn; // only warn and error are emitted
```


## Timing

Loggers can annotate messages with elapsed time using
[`startTimer`](../lib/src/utils/logger.dart#:~:text=startTimer) and
[`stopTimer`](../lib/src/utils/logger.dart#:~:text=stopTimer):

```dart
Services.log.startTimer();
Services.log.info('Loading assets');
// ... work ...
Services.log.info('Assets loaded'); // includes elapsed time
Services.log.stopTimer();
```


## Available loggers

### PrintLogger

The default logger. This will print the message to the console. For example:

```text
INFO: Game is starting up
DEBUG: Start time 17230
WARN: Sprite not found. Using fallback
DEBUG: End time 17411 
```


### PrintJsonLogger

Also prints to console, but adds additional data to the message and formats it
using JSON. The format of the JSON objects is:

```json
{
    "level": "debug|info|warn|error",
    "time": "2024-07-20T20:18:04.000Z",
    "message": "The message",
    "trace": "Stack trace",
    "timing": {
        "started": "2024-07-20T20:18:03.000Z",
        "now": "2024-07-20T20:18:04.000Z",
        "elapsed": 1000000
    }
}
```

`level`, `time` and `message` are always present. `trace` is added on `error`
messages only. `timing` is included while a timer is active (after
`startTimer()` and before `stopTimer()`).


### FileLogger

`FileLogger` extends `PrintJsonLogger` and writes its JSON output to a file in
the application's documents directory. Construct it with no arguments and then
call [`init(id)`](../lib/src/utils/logger.dart#:~:text=init) with the path you
want, relative to the documents folder. The extension `.log.json` is appended
automatically.

```dart
final logger = FileLogger();
await logger.init('logs/my_game'); // writes DOCUMENTS/logs/my_game.log.json
Services.log = logger;

// When you're done writing logs
logger.dispose();
```

Call [`dispose()`](../lib/src/utils/logger.dart#:~:text=dispose) to flush and
close the underlying file sink before the game exits.


## Custom loggers

Implement the [`Logger`](../lib/src/utils/logger.dart#:~:text=abstract+class+Logger)
interface to write your own logger - for example, to ship logs to a remote
service. Once instantiated, assign it to `Services.log` to make it active.
