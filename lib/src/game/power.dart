/// Seam for a platform plugin that can report the device's battery saver
/// state.
///
/// Sizzle is pure Dart and ships no implementation, so
/// `Device.isPowerSaveSupported` is `false` until a companion plugin
/// registers one into `Device.powerProvider`.
///
/// Deliberately narrow: battery *percentage* is not here, because an engine
/// cannot act on it sensibly and a game that wants it can reach for a
/// dedicated package. Power save mode is different - it is the user telling
/// the system to trade quality for endurance, which is exactly the signal a
/// game needs to drop to [FrameRateMode.softwareHalfRate].
///
/// **Do not rely on this on Wear OS.** Wear has a Clockwork-specific "Battery
/// Saver Mode" that is separate from Android's power save state: it does not
/// move `PowerManager.isPowerSaveMode`, does not write
/// `Settings.Global.low_power`, and has no public API. Verified on Pixel
/// Watch 3, where enabling it from Settings produces no observable change to
/// anything an app can read. A watch game will therefore see `false` here
/// even while the watch is visibly conserving power - and will separately see
/// ambient mode stop being delivered, since Wear suppresses always-on in that
/// state.
abstract class PowerProvider {
  /// Whether this platform can report power save state at all.
  bool get isSupported;

  /// Whether battery saver is on right now.
  bool get isPowerSaveMode;

  /// Begins delivering changes to [onChanged]. Called once when the game
  /// mounts; calling again replaces the callback.
  void listen({required void Function(bool isPowerSaveMode) onChanged});

  /// Stops delivering. Called when the game is torn down.
  void cancel();
}
