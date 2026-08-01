/// Strategy used by `SizzleGame` to decide how often the game paints.
///
/// The *simulation* rate is a separate knob (`SizzleGame.fixedUpdateFps`,
/// default 60) and is unaffected by this enum: `fixedUpdate` keeps running at
/// the full rate in every mode. Only the paint rate changes, which is what
/// costs GPU time (and, where the platform honours it, display power).
enum FrameRateMode {
  /// Paint on every vsync, at whatever rate the display runs at.
  ///
  /// Named `native` because `default` is a reserved word in Dart and cannot
  /// be used as an enum constant.
  native,

  /// Ask the platform to halve the *panel* refresh rate (on Android, via
  /// `Surface.setFrameRate`).
  ///
  /// This is the only mode that saves display power rather than just GPU
  /// work, but very few devices honour it - a panel that reports 60Hz support
  /// usually stays at 60Hz no matter what is requested. Sizzle therefore
  /// *measures* the resulting frame cadence rather than trusting the request,
  /// and falls back to [softwareHalfRate] (or [native]) when the request is
  /// ignored. See `SizzleGame.setFrameRateMode`.
  ///
  /// Requires a registered [HwFrameRateProvider] (`Device.hwFrameRateProvider`).
  /// Sizzle ships no native plugin, so without one this mode always resolves
  /// to its fallback.
  hardwareHalfRate,

  /// Halve the paint rate in software: the game loop's ticker is paused and
  /// Sizzle steps the engine every second physics tick instead.
  ///
  /// The panel keeps running at its native rate, so this saves GPU render
  /// work but no display power. Paints are still issued via `markNeedsPaint`
  /// and therefore stay vsync-aligned, which keeps judder low.
  softwareHalfRate,
}

/// Seam for a platform plugin that can change the display's refresh rate.
///
/// Sizzle itself is pure Dart and ships no implementation, so
/// `Device.isHWFrameRateSupported` is `false` until a companion plugin
/// registers one into `Device.hwFrameRateProvider`. Implementations are
/// best-effort: [setHardwareFrameRate] returning `true` only means the
/// request was accepted, never that the panel actually changed. Sizzle
/// verifies the outcome by measuring the real frame cadence.
abstract class HwFrameRateProvider {
  /// Whether this platform can accept refresh-rate requests at all.
  bool get isSupported;

  /// Requests that the display present at [fps]. Returns `true` if the
  /// request was accepted by the platform (not that it was honoured).
  Future<bool> setHardwareFrameRate(double fps);

  /// Releases any refresh-rate request previously made, returning the
  /// display to its default behaviour.
  Future<void> clear();
}
