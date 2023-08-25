import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flutter/services.dart';

import 'snap.dart';

/// A ply-sprite (sprite made up of many layers)
///
/// Sizzle includes a script that allows exporting ply-sprites from Aseprite.
class PlySpriteComponent extends PositionComponent with Snap {
  PlySpriteComponent(this.name);

  final String name;
  late final Image _image;
  late final _PlySpriteData _data;
  final Paint _paint = Paint();

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

  @override
  FutureOr<void> onLoad() async {
    _image = await Images().load("$name.png");
    _data = await _PlySpriteData.create(name);
    _anim = _data.animations.values.first;
    width = _data.width;
    height = _data.height;
    reset();
    play(nextAnimation);
    return super.onLoad();
  }

  /// Reset current animation back to the start
  void reset() {
    _animForward = _anim.direction != directionReverse;
    if (_animForward) {
      _frameIndex = 0;
    } else {
      _frameIndex = _anim.frames.length - 1;
    }
    _frame = _anim.frames[_frameIndex];
    _framePos = 0;
    anchor = Anchor(_anim.anchor.x / width, _anim.anchor.y / height);
  }

  /// Play an animation by [name]. If no [name] is specified will continue
  /// playing the current animation. By default this is the first animation
  /// in the file.
  void play([String? name]) {
    if (name != null) {
      if (!isLoaded) {
        nextAnimation = name;
      } else {
        final anim = _data.animations[name] ?? _data.animations.values.first;
        if (anim != _anim) {
          _anim = anim;
          reset();
        }
      }
    }
    _playing = true;
  }

  /// Stop playing an animation
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

  @override
  void update(double dt) {
    if (_playing) scrub(dt, true);
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    if (isLoaded) {
      canvas.drawAtlas(_image, _frame.transforms, _frame.rects, null, null, null, _paint);
    }
    super.render(canvas);
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

  static FutureOr<_PlySpriteData> create(String name) async {
    if (!_cache.containsKey(name)) {
      final json = jsonDecode(await rootBundle.loadString("${Images().prefix}$name.json"));
      final data = _PlySpriteData(json);
      _cache[name] = data;
    }
    return _cache[name]!;
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
