/// Seam for a platform plugin that can report ambient (always-on) mode.
///
/// Sizzle does not *support* ambient mode in the sense of rendering a
/// low-power screen. It only needs to know when the display has gone ambient
/// so it can stop the game, and this is the smallest interface that allows
/// that.
///
/// The reason it has to exist at all is that on Wear OS 6 and later an app
/// targeting SDK 36+ is always-on whether it wants to be or not: the activity
/// stays *resumed* when the watch dims, so no lifecycle callback arrives and
/// nothing would otherwise stop the game. Left unhandled, a game would keep
/// simulating and painting at full rate on a screen nobody is looking at.
/// There is no way to opt out of that behaviour, so Sizzle detects it and
/// pauses instead.
///
/// Sizzle is pure Dart and ships no implementation, so
/// `Device.isAmbientSupported` is `false` until a companion plugin registers
/// one into `Device.ambientProvider`. Games never call this directly -
/// `SizzleGame` drives it on mount and teardown, and the effect is visible
/// only as [PauseReason.ambient] appearing in `SizzleGame.pauseReasons`.
abstract class AmbientProvider {
  /// Whether this platform can report ambient mode at all.
  bool get isSupported;

  /// Begins delivering ambient transitions.
  ///
  /// [onChanged] fires with `true` on entering ambient and `false` on
  /// leaving. Called once when the game mounts; calling again replaces the
  /// callback.
  void listen({required void Function(bool isAmbient) onChanged});

  /// Stops delivering. Called when the game is torn down.
  void cancel();
}
