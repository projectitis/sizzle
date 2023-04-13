import 'dart:async';
import 'dart:math';

import 'package:sizzle/sizzle.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart' hide Route;

class SizzleGame extends FlameGame with SingleGameInstance, MouseMovementDetector, TapDetector {
  int _pointerEventId = 0;
  RouterComponent? _router;
  final Vector2 _targetSize = Vector2(320, 240);
  final Vector2 _maxSize = Vector2(320, 240);
  final Vector2 bitmapScale = Vector2.all(1.0);
  Rect viewWindow = Rect.fromLTWH(0.0, 0.0, 320.0, 240.0);
  Paint? _letterBoxPaint;

  SizzleGame({
    required Map<String, Component Function()> scenes,
    Vector2? targetSize,
    Vector2? maxSize,
    Color letterBoxColor = const Color(0xff000000),
  }) : super() {
    if (targetSize != null) _targetSize.setFrom(targetSize);
    _maxSize.setFrom(maxSize ?? _targetSize);
    _letterBoxPaint = Paint()..color = letterBoxColor;
    final Map<String, Route> routes = {};
    scenes.forEach((key, value) {
      routes[key] = Route(value);
    });
    add(_router = RouterComponent(initialRoute: scenes.keys.first, routes: routes));
  }

  @override
  FutureOr<void> onLoad() async {
    await Services.init();
    return super.onLoad();
  }

  @override
  void onGameResize(Vector2 canvasSize) {
    if (_targetSize.x != 0) {
      double s = min(canvasSize.x / _targetSize.x, canvasSize.y / _targetSize.y);
      double w = min(canvasSize.x, _maxSize.x * s);
      double h = min(canvasSize.y, _maxSize.y * s);
      bitmapScale.setValues(s, s);
      viewWindow = Rect.fromLTWH(
        (canvasSize.x - w) * 0.5,
        (canvasSize.y - h) * 0.5,
        w,
        h,
      );
    }
    super.onGameResize(canvasSize);
  }

  /// Override renderTree to set up letterbox
  @override
  void renderTree(Canvas c) {
    if (_targetSize.x != 0) {
      c.save();
      c.translate(viewWindow.left, viewWindow.top);
      super.renderTree(c);
      c.restore();

      if (viewWindow.width < size.x) {
        c.drawRect(Rect.fromLTWH(0.0, 0.0, viewWindow.left, viewWindow.height), _letterBoxPaint!);
        c.drawRect(Rect.fromLTWH(viewWindow.right, 0.0, viewWindow.left, viewWindow.height), _letterBoxPaint!);
      } else if (viewWindow.height < size.y) {
        c.drawRect(Rect.fromLTWH(0.0, 0.0, size.x, viewWindow.top), _letterBoxPaint!);
        c.drawRect(Rect.fromLTWH(0.0, viewWindow.bottom, size.x, viewWindow.top), _letterBoxPaint!);
      }
    } else {
      super.renderTree(c);
    }
  }

  void changeScene(String scene) {
    _router?.pushNamed(scene);
  }

  @override
  void onMouseMove(PointerHoverInfo info) {
    super.onMouseMove(info);

    for (final child in children) {
      //if (child is RiveSprite) {
      //  child.pointerMove(info.eventPosition.global);
      //}
    }
  }

  @override
  void onTapDown(TapDownInfo info) {
    super.onTapDown(info);

    for (final child in children) {
      //if (child is RiveSprite) {
      //  child.pointerDown(info.eventPosition.global, ++_pointerEventId);
      //}
    }
  }

  @override
  void onTapUp(TapUpInfo info) {
    super.onTapUp(info);

    for (final child in children) {
      //if (child is RiveSprite) {
      //  child.pointerUp(info.eventPosition.global);
      //}
    }
  }
}
