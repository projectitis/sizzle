import 'dart:ui';

import 'package:flame/components.dart';

import '../game/game.dart';

/// Base class for a top-level screen, level, or game state in a Sizzle game.
///
/// Each entry in [SizzleGame]'s `scenes:` map (or its `scene:`) is a
/// constructor reference to a [Scene] subclass. The subclass is instantiated
/// lazily by Flame's `RouterComponent` the first time the route is visited,
/// so any expensive work belongs in [onLoad] rather than the constructor.
///
/// A minimal scene only needs to extend [Scene]:
///
/// ```dart
/// class IntroScene extends Scene {
///   @override
///   Future<void> onLoad() async {
///     // Load assets, add child components.
///   }
/// }
///
/// SizzleGame(scenes: {'intro': IntroScene.new});
/// ```
///
/// If the scene needs constructor arguments, supply a closure in place of
/// `MyScene.new`:
///
/// ```dart
/// SizzleGame(scenes: {'level': () => LevelScene(currentLevel)});
/// ```
///
/// Scenes are Flame [Component]s, so children, lifecycle hooks (`onLoad`,
/// `onMount`, `onRemove`, etc.) and the priority/key API all behave as they
/// do in any other component. The mixed-in [HasGameReference] exposes the
/// running [SizzleGame] via `game`.
class Scene extends Component with HasGameReference<SizzleGame> {
  /// When `true`, [update] and [render] short-circuit so the scene's children
  /// are neither ticked nor drawn.
  ///
  /// Useful for pause menus, modal overlays, or temporarily freezing the
  /// world while a different scene is presented on top. Pausing only affects
  /// this scene - other mounted scenes (and the rest of the component tree)
  /// continue to run.
  bool paused = false;

  /// Advances the scene's children by [dt] seconds. Skipped while [paused].
  @override
  void update(double dt) {
    if (paused) return;
    super.update(dt);
  }

  /// Draws the scene's children. Skipped while [paused], leaving the previous
  /// frame visible.
  @override
  void render(Canvas canvas) {
    if (paused) return;
    super.render(canvas);
  }

  /// Switches the running [SizzleGame] to the scene registered under [scene].
  ///
  /// Convenience wrapper around `game.changeScene(name)` so that scenes can
  /// trigger navigation without reaching for the game reference directly. The
  /// named route must exist in the `scenes:` map passed to [SizzleGame] or
  /// the underlying call will assert.
  ///
  /// If [replace] is `true`, the new scene takes the place of the current
  /// route on the navigation stack instead of being pushed on top of it.
  void changeScene(String scene, {bool replace = false}) {
    game.changeScene(scene, replace: replace);
  }
}
