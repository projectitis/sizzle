/// Why a [SizzleGame] is not running.
///
/// The engine has a single `paused` flag but several independent things that
/// want to stop it, and they overlap: the app can be backgrounded while the
/// watch is in ambient mode while the title has its own pause menu open.
/// Tracking them as a set means the game resumes when the *last* reason
/// clears, rather than the first one to notice.
///
/// Read the current set from `SizzleGame.pauseReasons`.
///
/// Note that the frame rate mode is deliberately not a member.
/// [FrameRateMode.softwareHalfRate] also pauses the ticker, but as an
/// implementation detail rather than an intent to stop the game - it still
/// steps the engine on its own cadence. That case is derived from the
/// effective mode instead, which is what makes "paused for a real reason"
/// and "paused to control the paint rate" distinguishable.
enum PauseReason {
  /// The OS backgrounded, hid or detached the app. Outranks everything:
  /// nothing should simulate or paint when there is no surface to paint to.
  backgrounded,

  /// The device entered ambient (always-on) mode. The game is repainted at
  /// most once per ambient tick and the simulation does not run.
  ambient,

  /// The title itself called `pauseEngine()`, `resumeEngine()`, or set
  /// `paused`. A pause menu, a modal, a cutscene - whatever the game means
  /// by "stopped".
  user,
}
