import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart' hide Route;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';

import './scene.dart';
import '../math/math.dart';
import '../utils/services.dart';

/// The root [FlameGame] for a Sizzle title.
///
/// `SizzleGame` adds three things on top of `FlameGame`:
///
/// 1. **A target/max sizing model with letterboxing.** Pass [targetSize]
///    (the always-visible game area) and optionally [maxSize] (the largest
///    drawable area). Sizzle picks a uniform scale that keeps the target
///    area fully on-screen, fills outwards up to the max, and draws a
///    letterbox in [letterBoxColor] for anything beyond. Set
///    [scaleToWholePixels] for crisp pixel-art rendering, or [scale] to
///    clamp the auto-fit factor.
/// 2. **Scene routing.** Provide either a single [scene] or a map of named
///    [scenes]; the first entry is the initial route. Each value is a
///    *constructor reference* (`MyScene.new` or a closure) that the
///    underlying [RouterComponent] invokes lazily on first visit. Switch
///    scenes with [changeScene] from anywhere with a game reference, or
///    `Scene.changeScene` from inside a scene.
/// 3. **Coordinate-transformed input** so taps, drags and hover hit the
///    same components they appear over once the letterbox translation has
///    been applied (see [componentsAtPoint]).
///
/// Read-only views of the resulting layout are exposed via [viewWindow]
/// (the visible area inside the letterbox), [gameWindow] (the full max
/// area, which may extend past the screen), [safeWindow] (the slice that
/// is always visible regardless of aspect ratio), [gameWindowOffset] (the
/// max area's offset from the canvas), and [snapScale] (the current
/// pixel-to-screen ratio used by `Snap` components).
///
/// A typical entry point:
///
/// ```dart
/// void main() {
///   final game = SizzleGame(
///     scenes: {
///       'menu': MenuScene.new,
///       'game': GameScene.new,
///     },
///     targetSize: Vector2(240, 180),
///     maxSize: Vector2(360, 180),
///   );
///   runApp(GameWidget(game: game));
/// }
/// ```
class SizzleGame extends FlameGame
    with SingleGameInstance, TapCallbacks, KeyboardEvents {
  /// Router component that owns the navigation stack of scenes. Exposed
  /// publicly via [router].
  late RouterComponent _router;

  final Vector2 _targetSize = Vector2(320, 240);

  /// The always-visible game area, in unscaled game pixels. Common sizes
  /// are 320x240, 160x120 etc. Set via the `targetSize` constructor
  /// parameter; once the game is constructed this getter is read-only.
  Vector2 get targetGameSize => _targetSize;

  final Vector2 _maxSize = Vector2(320, 240);

  /// The maximum drawable area, in unscaled game pixels.
  ///
  /// May be larger than [targetGameSize] to extend the visible area beyond
  /// the guaranteed-on-screen target. Anything outside [targetGameSize] is
  /// not guaranteed to be displayed on every aspect ratio, so keep
  /// gameplay-critical content inside the target area.
  Vector2 get maxGameSize => _maxSize;

  /// The size of one game pixel in screen pixels after the view window has
  /// been scaled. Updated automatically by [onGameResize]; bitmap sprites
  /// and `Snap` components read this to render at the right scale and snap
  /// to whole pixels.
  final Vector2 snapScale = Vector2.all(1.0);

  /// When `true`, [snapScale] is rounded down to an integer so each game
  /// pixel covers a whole number of screen pixels. Recommended for
  /// pixel-art games.
  bool scaleToWholePixels = false;

  /// Optional clamp on the auto-fit scale factor. When non-zero the scale
  /// chosen by [onGameResize] is restricted to this `[min, max]` range.
  Range scale = Range.zero;

  /// The visible game area inside the letterbox, in screen pixels.
  /// Updated by [onGameResize].
  final MutableRectangle<double> viewWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// The full max-size game area in screen pixels. May extend past the
  /// visible canvas - see [viewWindow] for what the user actually sees.
  final MutableRectangle<double> gameWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// The slice of [gameWindow] that is guaranteed to be visible at every
  /// aspect ratio. May be smaller than [viewWindow]. UI and critical game
  /// elements should stay inside this rectangle.
  final MutableRectangle<double> safeWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// Offset of [gameWindow] from the top-left of the canvas, in screen
  /// pixels. Negative when the max area extends past the canvas edges.
  final Vector2 gameWindowOffset = Vector2.zero();

  /// Paint used to draw the letterbox bars. Only the colour is consulted.
  final Paint _letterBoxPaint = Paint();

  /// Optional cleanup callback. Invoked from [onDispose] before the
  /// superclass tears down, giving the game a chance to release resources
  /// (file handles, audio sinks, services) it owns.
  Function? onCleanup;

  /// Tracks whether [onDispose] has already run, since some platforms can
  /// fire multiple lifecycle events that each route through it.
  bool _isDisposed = false;

  /// Creates a new Sizzle game.
  ///
  /// Exactly one of [scene] (a single scene) or [scenes] (a named map)
  /// must be supplied. For [scenes], the first entry becomes the initial
  /// route. Each value is a constructor reference - typically `MyScene.new`,
  /// or `() => MyScene(arg)` if the scene needs constructor arguments.
  ///
  /// [targetSize] is the always-visible game area; [maxSize] (defaults to
  /// [targetSize]) lets you draw beyond it without the extra area becoming
  /// the new minimum visible area. [letterBoxColor] is painted around
  /// [maxSize] when the canvas is larger than the max area.
  /// [scaleToWholePixels] forces integer pixel scaling for crisp pixel-art.
  /// [scale] clamps the auto-fit scale factor.
  SizzleGame({
    Map<String, Component Function()>? scenes,
    Component Function()? scene,
    Vector2? targetSize,
    Vector2? maxSize,
    Color letterBoxColor = const Color(0xff000000),
    this.scaleToWholePixels = false,
    Range? scale,
  }) : super() {
    assert(
      scene != null || scenes != null,
      'A scene or scenes must be provided',
    );
    assert(
      !(scene != null && scenes != null),
      'Provide either a scene or list of scenes, not both',
    );

    if (targetSize != null) {
      _targetSize.setFrom(targetSize);
    }
    _maxSize.setFrom(maxSize ?? _targetSize);

    if (scale != null) {
      this.scale = scale;
    }

    _letterBoxPaint.color = letterBoxColor;

    final Map<String, Route> routes = {};
    if (scenes != null) {
      scenes.forEach((key, value) {
        routes[key] = Route(value);
      });
    } else if (scene != null) {
      routes['default'] = Route(scene);
    }
    add(
      _router =
          RouterComponent(initialRoute: routes.keys.first, routes: routes),
    );

    // Route lifecycle events through onDispose so platform-specific exit
    // paths (close button, OS shutdown) all converge on the same cleanup.
    AppLifecycleListener(
      onDetach: () {
        onDispose();
      },
      onExitRequested: () async {
        onDispose();
        return AppExitResponse.exit;
      },
    );
  }

  /// Recomputes [snapScale], [viewWindow], [gameWindow], [safeWindow] and
  /// [gameWindowOffset] for the new canvas size, then forwards to
  /// [FlameGame.onGameResize]. Honours [scale] and [scaleToWholePixels].
  @override
  void onGameResize(Vector2 canvasSize) {
    if (_targetSize.x != 0) {
      double s =
          min(canvasSize.x / _targetSize.x, canvasSize.y / _targetSize.y);
      if (scale.isNotZero) {
        s = scale.clamp(s);
      }
      if (scaleToWholePixels) s = max(s.floorToDouble(), 1.0);
      double xMax = _maxSize.x * s;
      double yMax = _maxSize.y * s;
      double xMin = _targetSize.x * s;
      double yMin = _targetSize.y * s;
      double w = min(canvasSize.x, xMax);
      double h = min(canvasSize.y, yMax);
      snapScale.setValues(s, s);
      viewWindow.setValues(
        (canvasSize.x - w) * 0.5,
        (canvasSize.y - h) * 0.5,
        w,
        h,
      );
      safeWindow.setValues(
        (xMax - xMin) * 0.5,
        (yMax - yMin) * 0.5,
        xMin,
        yMin,
      );
      gameWindow.setValues(
        (xMax - w) * 0.5,
        (yMax - h) * 0.5,
        xMax,
        yMax,
      );
      gameWindowOffset.setValues(
        (xMax - canvasSize.x) * 0.5,
        (yMax - canvasSize.y) * 0.5,
      );
    }
    super.onGameResize(canvasSize);
  }

  /// Ticks Flame's component tree, then drives any global per-frame
  /// services (currently the tween service). Pausing the game pauses
  /// these services for free because Flame stops calling [update].
  @override
  void update(double dt) {
    super.update(dt);
    Services.tween.update(dt);
  }

  /// Transforms event coordinates to account for the letterbox offset
  /// applied in [renderTree].
  ///
  /// Without this, hit testing would use raw screen coordinates while
  /// components are rendered with the letterbox translation, causing
  /// every tap/drag/hover event to miss its target.
  @override
  Iterable<Component> componentsAtPoint(
    Vector2 point, [
    List<Vector2>? nestedPoints,
  ]) {
    if (_targetSize.x != 0) {
      return super.componentsAtPoint(
        point -
            Vector2(
              viewWindow.left - gameWindow.left,
              viewWindow.top - gameWindow.top,
            ),
        nestedPoints,
      );
    }
    return super.componentsAtPoint(point, nestedPoints);
  }

  /// Translates the canvas to the [viewWindow] origin, renders the
  /// component tree, and fills any space outside [viewWindow] with the
  /// letterbox colour.
  @override
  void renderTree(Canvas c) {
    if (_targetSize.x != 0) {
      c.save();
      c.translate(
        viewWindow.left - gameWindow.left,
        viewWindow.top - gameWindow.top,
      );
      super.renderTree(c);
      c.restore();

      if (viewWindow.width < size.x) {
        // Left
        c.drawRect(
          Rect.fromLTWH(
            0.0,
            viewWindow.top.floorToDouble(),
            viewWindow.left,
            viewWindow.bottom.ceilToDouble(),
          ),
          _letterBoxPaint,
        );
        // Right
        c.drawRect(
          Rect.fromLTWH(
            viewWindow.right,
            viewWindow.top.floorToDouble(),
            viewWindow.left,
            viewWindow.bottom.ceilToDouble(),
          ),
          _letterBoxPaint,
        );
      }
      if (viewWindow.height < size.y) {
        // Top
        c.drawRect(
          Rect.fromLTWH(0.0, 0.0, size.x, viewWindow.top),
          _letterBoxPaint,
        );
        // Bottom
        c.drawRect(
          Rect.fromLTWH(0.0, viewWindow.bottom, size.x, viewWindow.top),
          _letterBoxPaint,
        );
      }
    } else {
      super.renderTree(c);
    }
  }

  /// Switches to the scene registered under [scene].
  ///
  /// Pushes the route to the top of the navigation stack. If the route is
  /// already in the stack it is moved to the top instead of being mounted
  /// twice. If it is already the top, this is a no-op. The scene's page
  /// is built lazily on first visit.
  ///
  /// When [replace] is `true` the current top route is removed first, so
  /// the new scene takes its place rather than stacking on top of it.
  ///
  /// The named route must exist in the `scenes:` map passed to the
  /// constructor or this will assert.
  void changeScene(String scene, {bool replace = false}) {
    assert(
      _router.routes.keys.contains(scene),
      'The scene \'$scene\' does not exist',
    );

    _router.pushNamed(scene, replace: replace);
  }

  /// The scene currently on top of the navigation stack, or `null` while
  /// the initial route is still mounting.
  Scene? get currentScene => _router.currentRoute.hasChildren
      ? _router.currentRoute.lastChild() as Scene
      : null;

  /// The underlying Flame [RouterComponent] driving scene navigation.
  ///
  /// Exposed for advanced use cases - inspecting the navigation stack,
  /// driving custom transitions, or popping routes - that the convenience
  /// methods on [SizzleGame] and [Scene] don't cover.
  RouterComponent get router => _router;

  /// Runs [onCleanup] (if set) and tears down the game.
  ///
  /// Idempotent: subsequent calls are no-ops, which lets multiple
  /// platform lifecycle paths (`onDetach`, `onExitRequested`, manual
  /// disposal) safely converge here.
  @override
  void onDispose() {
    if (!_isDisposed) {
      onCleanup?.call();
      super.onDispose();
      _isDisposed = true;
    }
  }
}
