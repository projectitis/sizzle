import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart' hide Route;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';

import './scene.dart';
import '../math/math.dart';

class SizzleGame extends FlameGame
    with SingleGameInstance, TapCallbacks, KeyboardEvents {
  /// Router component to manage scenes
  late RouterComponent _router;

  /// Target size in scaled pixels. Common sizes are 320x240, 160x120 etc
  final Vector2 _targetSize = Vector2(320, 240);
  Vector2 get targetGameSize => _targetSize;

  /// Set a maximum size that is larger than the [targetSize] to extend the
  /// visible area of the game beyond the target size. You should ensure that
  /// all action occurs in the target area because anything outside that is not
  /// guaranteed to be displayed.
  final Vector2 _maxSize = Vector2(320, 240);
  Vector2 get maxGameSize => _maxSize;

  /// The size of each pixel once the view window has been scaled. This is used
  /// by bitmap sprites to display at the correct scale and to snap to whole
  /// pixels.
  final Vector2 snapScale = Vector2.all(1.0);

  /// Always ensure that the [snapScale] is in whole pixels
  bool scaleToWholePixels = false;

  /// Scale the game to fit the whole screen
  Range scale = Range.zero;

  /// The visible game window inside the letterbox
  final MutableRectangle<double> viewWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// The maximum size of the game. Not all parts may be visible
  final MutableRectangle<double> gameWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// The visible safe window. May be smaller than the view window, but
  /// guaranteed to be visible
  final MutableRectangle<double> safeWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// The offset of the game window from the top left of the screen
  final Vector2 gameWindowOffset = Vector2.zero();

  /// The paint used to draw the letterbox. Only the color is used.
  /// Usually black.
  final Paint _letterBoxPaint = Paint();

  /// User-defined cleanup function
  Function? onCleanup;

  /// Flag to indicate if the game has been disposed already
  bool _isDisposed = false;

  /// Create a new sizzle game
  ///
  /// Either a [scene] or map of [scenes] should be provided. The game will
  /// start on the first scene in the list. Set a target screen size using
  /// [targetSize], and use [maxSize] to support a larger game area. Set the
  /// color of the letterbox with [letterBoxColor].
  SizzleGame({
    Map<String, Component Function()>? scenes,
    Component Function()? scene,
    Vector2? targetSize,
    Vector2? maxSize,
    Color letterBoxColor = const Color(0xff000000),
    this.scaleToWholePixels = false,
    Range? scale,
    double? maxFPS,
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

    // Handle game exit
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

  /// Calculate new view window size and snap scaling when the game resizes
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

  /// Letterbox the view window
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

  /// Handle scene changes using the Flame router.
  ///
  /// Pushes the route specified by [name] to the top of the navigation stack.
  /// If the route is already on the stack, it will just be moved to the top.
  /// Otherwise the route will be mounted and added at the top. We will also
  /// initiate building the route's page if it hasn't been built before. If the
  /// route is already on top of the stack, this method will do nothing.
  void changeScene(String scene, {bool replace = false}) {
    assert(
      _router.routes.keys.contains(scene),
      'The scene \'$scene\' does not exist',
    );

    _router.pushNamed(scene, replace: replace);
  }

  /// Get the current scene
  Scene? get currentScene => _router.currentRoute.hasChildren
      ? _router.currentRoute.lastChild() as Scene
      : null;

  /// Handle dispose and cleanup
  @override
  void onDispose() {
    // Ensure game is only disposed once. Different lifecycle events may end
    // up calling this method multiple times on certain platforms.
    if (!_isDisposed) {
      onCleanup?.call();
      super.onDispose();
      _isDisposed = true;
    }
  }
}
