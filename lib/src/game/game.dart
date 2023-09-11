import 'dart:math';

import 'package:sizzle/sizzle.dart';
import 'package:flutter/material.dart' hide Route;

class SizzleGame extends FlameGame with SingleGameInstance, HasHoverables {
  /// Router component to manage scenes
  late RouterComponent _router;

  /// Target size in scaled pixels. Common sizes are 320x240, 160x120 etc
  final Vector2 _targetSize = Vector2(320, 240);
  get targetGameSize => _targetSize;

  /// Set a maximum size that is larger than the [targetSize] to extend the
  /// visible area of the game beyond the target size. You should ensure that
  /// all action occurs in the target area because anything outside that is not
  /// guaranteed to be displayed.
  final Vector2 _maxSize = Vector2(320, 240);
  get maxGameSize => _maxSize;

  /// The size of each pixel once the view window has been scaled. This is used
  /// by bitmap sprites to display at the correct scale and to snap to whole pixels.
  final Vector2 snapScale = Vector2.all(1.0);

  /// Always ensure that the [snapScale] is in whole pixels
  bool scaleToWholePixels = false;

  /// The visible game window inside the letterbox
  final MutableRectangle<double> viewWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// The maximum size of the game. Not all parts may be visible
  final MutableRectangle<double> gameWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  /// The visible safe window. May be smaller than the view window, but guaranteed to be visible
  final MutableRectangle<double> safeWindow =
      MutableRectangle(0.0, 0.0, 320.0, 240.0);

  final Vector2 gameWindowOffset = Vector2.zero();

  /// The paint used to draw the letterbox. Only the color is used. Usually black.
  final Paint _letterBoxPaint = Paint();

  /// Create a new sizzle game
  ///
  /// Either a [scene] or map of [scenes] should be provided. The game will start on
  /// the first scene in the list. Set a target screen size using [targetSize], and
  /// use [maxSize] to support a larger game area. Set the color of the letterbox with
  /// [letterBoxColor].
  SizzleGame(
      {Map<String, Component Function()>? scenes,
      Component Function()? scene,
      Vector2? targetSize,
      Vector2? maxSize,
      Color letterBoxColor = const Color(0xff000000),
      this.scaleToWholePixels = false,})
      : super() {
    assert(
        scene != null || scenes != null, 'A scene or scenes must be provided',);
    assert(!(scene != null && scenes != null),
        'Provide either a scene or list of scenes, not both',);

    if (targetSize != null) _targetSize.setFrom(targetSize);
    _maxSize.setFrom(maxSize ?? _targetSize);

    _letterBoxPaint.color = letterBoxColor;

    final Map<String, Route> routes = {};
    if (scenes != null) {
      scenes.forEach((key, value) {
        routes[key] = Route(value);
      });
    } else if (scene != null) {
      routes['default'] = Route(scene);
    }
    add(_router =
        RouterComponent(initialRoute: routes.keys.first, routes: routes),);

    // Set up services
    Services.init(this);
  }

  /// Calculate new view window size and snap scaling when the game resizes
  @override
  void onGameResize(Vector2 canvasSize) {
    if (_targetSize.x != 0) {
      double s =
          min(canvasSize.x / _targetSize.x, canvasSize.y / _targetSize.y);
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
          viewWindow.left - gameWindow.left, viewWindow.top - gameWindow.top,);
      super.renderTree(c);
      c.restore();

      if (viewWindow.width < size.x) {
        c.drawRect(Rect.fromLTWH(0.0, 0.0, viewWindow.left, viewWindow.height),
            _letterBoxPaint,);
        c.drawRect(
            Rect.fromLTWH(
                viewWindow.right, 0.0, viewWindow.left, viewWindow.height,),
            _letterBoxPaint,);
      } else if (viewWindow.height < size.y) {
        c.drawRect(
            Rect.fromLTWH(0.0, 0.0, size.x, viewWindow.top), _letterBoxPaint,);
        c.drawRect(
            Rect.fromLTWH(0.0, viewWindow.bottom, size.x, viewWindow.top),
            _letterBoxPaint,);
      }
    } else {
      super.renderTree(c);
    }
  }

  /// Handle scene changes using the Flame router.
  ///
  /// Pushes the route specified by [name] to the top of the navigation stack. If the route is already on the stack,
  /// it will just be moved to the top. Otherwise the route will be mounted and added at the top. We will also initiate building the
  /// route's page if it hasn't been built before. If the route is already on top of the stack, this method will do
  /// nothing.
  void changeScene(String scene, {bool replace = false}) {
    assert(_router.routes.keys.contains(scene),
        'The scene \'$scene\' does not exist',);

    _router.pushNamed(scene, replace: replace);
  }
}
