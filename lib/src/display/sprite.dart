import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:sizzle/src/game/services.dart';

import 'snap.dart';

/// A PlySprite is an animated sprite made up of many layers. The format is
/// very space-efficient because it re-uses a lot of parts that make up the
/// sprite, resulting in a much smaller image (sprite sheet).
///
/// A 'part' of a PlySprite can be re-used on many frames. A single part
/// can also be rotated (in 90 degree steps) and re-used without making the
/// sprite sheet (image) bigger.
///
/// The format was originally intended for systems that have much smaller
/// memory (such as microcontrollers), but is useful for any purpose that
/// benefits from a smaller memory or bundle size. It's especially handy for
/// reasonably small sprites (like you get in pixel-art games) and if you
/// have a character with a large number of animations (walk, jump, pick-up,
/// talk, etc). The resulting sprite sheet will be much, much smaller.
///
/// Sizzle includes a script that allows exporting ply-sprites from Aseprite.
/// See the comments in `/scripts/aseprite/ply-sprite.lua` for how to use it.
///
/// The format is quite straight-forward and exporters could be implemented quite
/// easily for other applications.
class PlySprite {
  /// Create a new PlySprite given the source [image] and the associated
  /// [jsonData]. Use the factory method [fromPath] to load a PlySprite
  /// directly from the assets.
  PlySprite._(this._image, this._data) {
    _anim = _data.animations.values.first;
    _size.x = _data.width;
    _size.y = _data.height;
    _reset();
  }

  /// Create a new PlySprite from an asset. A PlySprite consist of a PNG image
  /// and a JSON file with matching names (for example `mysprite.png` and
  /// `mysprite.json`).
  static Future<PlySprite> fromPath(String path) async {
    if (path.lastIndexOf('.') >= 0) {
      path = path.substring(0, path.lastIndexOf('.'));
    }
    final image = await Services.loadImage("$path.png");
    final data = await _PlySpriteData.create(path);
    return PlySprite._(image, data);
  }

  late final Image _image;
  late final _PlySpriteData _data;
  final Vector2 _size = Vector2.zero();
  final Paint _paint = Paint();
  Anchor _anchor = Anchor.topLeft;

  late _PlyAnimation _anim;
  bool _animForward = true;
  String? nextAnimation;

  late _PlyFrame _frame;
  int _frameIndex = 0;
  double _framePos = 0;

  bool _playing = false;
  get isPlaying => _playing;

  static int directionForward = 0;
  static int directionReverse = 1;
  static int directionPingpong = 2;

  /// Reset current animation back to the start
  void _reset() {
    _animForward = _anim.direction != directionReverse;
    if (_animForward) {
      _frameIndex = 0;
    } else {
      _frameIndex = _anim.frames.length - 1;
    }
    _frame = _anim.frames[_frameIndex];
    _framePos = 0;
    _anchor = Anchor(_anim.anchor.x / _size.x, _anim.anchor.y / _size.y);
  }

  /// Play the [animation]. If no [animation] is specified it will start or
  /// continue playing the current animation queue and will ignore [queue].
  /// If no animation has been played previously, by default this is the first
  /// animation in the file.
  ///
  /// Calling play with an [animation], and [queue] set to `false`, will stop
  /// all current animations and clear the queue. If [queue] is set to `true`,
  /// the [animation] will be added to the end of the queue and will play in
  /// sequence.
  void play(String? animation, {bool queue = false}) {
    if (animation != null) {
      final anim = _data.animations[animation] ?? _data.animations.values.first;
      if (anim != _anim) {
        _anim = anim;
        _reset();
      }
    }
    _playing = true;
  }

  /// Play all [animations]. This will stop all current animations and clear
  /// the queue. If [queue] is set to `true`, the [animations] will be added
  /// to the end of the queue and will play in sequence.
  void playAll(List<String> animations, {bool queue = false}) {
    assert(false, 'Not yet implemented');
  }

  /// Stop playing an animation. To continue again
  void stop() {
    _playing = false;
  }

  /// Set the position to [pos]. If [advance] is true, will advance
  /// from the current position.
  void scrub(double pos, [bool advance = false]) {
    int newIndex = _frameIndex;
    if (!advance) {
      _framePos = 0;
      if (_anim.direction == directionReverse) {
        newIndex = _anim.frames.length - 1;
        _animForward = false;
      } else {
        newIndex = 0;
        _animForward = true;
      }
      if (newIndex != _frameIndex) {
        _frameIndex = newIndex;
        _frame = _anim.frames[_frameIndex];
      }
    }
    double r;
    while (pos > 0) {
      r = (_frame.duration - _framePos) - pos;
      if (r < 0) {
        if (_animForward) {
          newIndex++;
          if (newIndex >= _anim.frames.length) {
            if (_anim.direction == directionPingpong) {
              newIndex = _anim.frames.length - 2;
              if (newIndex < 0) newIndex = 0;
              _animForward = false;
            } else {
              newIndex = 0;
            }
          }
        } else {
          newIndex--;
          if (newIndex < 0) {
            if (_anim.direction == directionPingpong) {
              newIndex = 1;
              if (_anim.frames.length < 2) newIndex = 0;
              _animForward = true;
            } else {
              newIndex = _anim.frames.length - 1;
            }
          }
        }
        _frame = _anim.frames[newIndex];
        _framePos = 0;
        pos += r;
      } else {
        _framePos += pos;
        pos = -1.0;
      }
    }
    if (newIndex != _frameIndex) {
      _frameIndex = newIndex;
      _frame = _anim.frames[_frameIndex];
    }
  }

  void update(double dt) {
    if (_playing) scrub(dt, true);
  }

  void render(Canvas canvas) {
    canvas.drawAtlas(_image, _frame.transforms, _frame.rects, null, null, null, _paint);
  }
}

class _PlyFrame {
  _PlyFrame(this.duration);
  final double duration;
  final List<RSTransform> transforms = [];
  final List<Rect> rects = [];

  void addPly(Rect part, int orientation, double x, double y) {
    double rot = 0;
    double ox = 0;
    double oy = 0;
    if (orientation == 4) {
      rot = pi * 0.5;
      ox = part.width;
    } else if (orientation == 3) {
      rot = pi;
      oy = part.height;
      ox = part.width;
    } else if (orientation == 7) {
      rot = pi * 1.5;
      oy = part.height;
    }
    transforms.add(RSTransform.fromComponents(
      rotation: rot,
      scale: 1.0,
      anchorX: 0.0,
      anchorY: 0.0,
      translateX: x + ox,
      translateY: y + oy,
    ));
    rects.add(part);
  }
}

class _PlyAnimation {
  _PlyAnimation(this.direction, double x, double y) : anchor = Vector2(x, y);
  final Vector2 anchor;
  final int direction;
  final List<_PlyFrame> frames = [];
}

class _PlySpriteData {
  static final Map<String, _PlySpriteData> _cache = {};

  static FutureOr<_PlySpriteData> create(String path) async {
    if (!_cache.containsKey(path)) {
      final data = _PlySpriteData(await Services.loadJson("$path.json"));
      _cache[path] = data;
    }
    return _cache[path]!;
  }

  _PlySpriteData(dynamic json) {
    /// Verbose JSON
    if (json is Map) {
      assert(json.containsKey('width'), 'root.width not found');
      assert(json.containsKey('height'), 'root.height not found');
      assert(json['parts'] is List, 'root.parts must be an array');
      width = json['width'].toDouble();
      height = json['height'].toDouble();

      for (final part in json['parts']) {
        assert(part.containsKey('x'), 'root.parts[n].x not found');
        assert(part.containsKey('y'), 'root.parts[n].y not found');
        assert(part.containsKey('width'), 'root.parts[n].width not found');
        assert(part.containsKey('height'), 'root.parts[n].height not found');
        parts.add(Rect.fromLTWH(
          part['x'].toDouble(),
          part['y'].toDouble(),
          part['width'].toDouble(),
          part['height'].toDouble(),
        ));
      }

      assert(json.containsKey('animations'), 'root.animations array not found');
      assert(json['animations'] is Map, 'root.animations must be an object');
      json['animations'].forEach((name, animData) {
        final anim = _PlyAnimation(
          animData['direction'],
          animData['anchor']['x'].toDouble(),
          animData['anchor']['y'].toDouble(),
        );

        animData['frames'].forEach((frameData) {
          final frame = _PlyFrame(frameData['duration']);
          frameData['parts'].forEach((partData) {
            frame.addPly(
              parts[partData['index']],
              partData['orientation'],
              partData['x'].toDouble(),
              partData['y'].toDouble(),
            );
          });
          anim.frames.add(frame);
        });
        animations[name] = anim;
      });
    }

    /// Condensed JSON
    else {
      assert(json.length == 3, 'root: 3 arrays expected [[], [], []]');
      assert(json[0] is List && json[0].length == 2, 'root[0]: size of sprite expected [int, int]');
      width = json[0][0].toDouble();
      height = json[0][1].toDouble();

      assert(json[1] is List, 'root[1]: parts array expected [...]');
      for (final part in json[1]) {
        assert(part is List && part.length == 4, 'root[1][n]: part array expected [int, int, int, int]');
        parts.add(Rect.fromLTWH(
          part[0].toDouble(),
          part[1].toDouble(),
          part[2].toDouble(),
          part[3].toDouble(),
        ));
      }

      assert(json[2] is List, 'root[2]: animation array expected []');
      for (final a in json[2]) {
        assert(a is List && a.length == 4, 'root[2][n]: animation array expected [string, int, [int, int], [...]]');
        assert(a[0] is String, 'root[2][n][0]: animation name expected. string');
        assert(a[1] is num, 'root[2][n][1]: animation direction expected. int');
        assert(a[2] is List && a[2].length == 2, 'root[2][n][2]: animation anchor expected [int, int]');
        final anim = _PlyAnimation(
          a[1],
          a[2][0].toDouble(),
          a[2][1].toDouble(),
        );

        assert(a[3] is List, 'root[2][n][3]: animation frames array expected [...]');
        for (final f in a[3]) {
          assert(f is List && f.length == 2, 'root[2][n][3][n]: frame array expected [double, [...]]');
          final frame = _PlyFrame(f[0].toDouble());

          assert(f[1] is List, 'root[2][n][3][n][1]: ply array expected [...]');
          for (final p in f[1]) {
            assert(p is List && p.length == 4, 'root[2][n][3][n][1][n]: ply array expected [int, int, int, int]');
            frame.addPly(
              parts[p[0]],
              p[1],
              p[2].toDouble(),
              p[3].toDouble(),
            );
          }

          anim.frames.add(frame);
        }

        animations[a[0]] = anim;
      }
    }
  }

  late final double width;
  late final double height;
  final List<Rect> parts = [];
  final Map<String, _PlyAnimation> animations = {};
}

class PlySpriteComponent extends PositionComponent {
  PlySpriteComponent(this.sprite) {
    anchor = sprite._anchor;
    size = sprite._size;
  }

  /// Create a new PlySpriteComponent from an asset. A PlySprite consist of a
  /// PNG image and a JSON file with matching names (for example `mysprite.png`
  /// and `mysprite.json`).
  static Future<PlySpriteComponent> fromPath(String path) async {
    return PlySpriteComponent(await PlySprite.fromPath(path));
  }

  final PlySprite sprite;

  /// Play the [animation]. If no [animation] is specified it will start or
  /// continue playing the current animation queue and will ignore [queue].
  /// If no animation has been played previously, by default this is the first
  /// animation in the file.
  ///
  /// Calling play with an [animation], and [queue] set to `false`, will stop
  /// all current animations and clear the queue. If [queue] is set to `true`,
  /// the [animation] will be added to the end of the queue and will play in
  /// sequence.
  void play(String? animation, {bool queue = false}) {
    sprite.play(animation, queue: queue);
    // Each animation can have a different anchor
    // TODO: When queue is implemented, this needs to be done onAnimationStart
    anchor = sprite._anchor;
  }

  /// Play all [animations]. This will stop all current animations and clear
  /// the queue. If [queue] is set to `true`, the [animations] will be added
  /// to the end of the queue and will play in sequence.
  void playAll(List<String> animations, {bool queue = false}) {
    sprite.playAll(animations, queue: queue);
  }

  /// Stop playing an animation. To continue again
  void stop() {
    sprite.stop();
  }

  /// Set the position to [pos]. If [advance] is true, will advance
  /// from the current position.
  void scrub(double pos, [bool advance = false]) {
    sprite.scrub(pos, advance);
  }

  @override
  void update(double dt) {
    sprite.update(dt);
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    sprite.render(canvas);
    super.render(canvas);
  }
}

class SnapPlySpriteComponent extends PlySpriteComponent with Snap {
  SnapPlySpriteComponent(PlySprite sprite) : super(sprite);

  /// Create a new SnapPlySpriteComponent from an asset. A PlySprite consist of a
  /// PNG image and a JSON file with matching names (for example `mysprite.png`
  /// and `mysprite.json`).
  static Future<SnapPlySpriteComponent> fromPath(String path) async {
    return SnapPlySpriteComponent(await PlySprite.fromPath(path));
  }
}
