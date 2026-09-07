/// A writable destination for `FileLogger` output.
///
/// Obtained from `openLogSink` in the platform shim, which returns `null` on
/// platforms with no writable file system (currently web).
abstract class LogSink {
  /// Append [data] to the sink.
  void write(String data);

  /// Flush and close the sink. The sink must not be written to afterwards.
  Future<void> close();
}
