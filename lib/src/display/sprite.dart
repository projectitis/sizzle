import 'dart:async';
import 'dart:convert';
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
  late final PlySpriteData _data;

  // The active animation
  late PlyAnimation _anim;

  // The current advance direction
  bool _animForward = true;

  // The active frame
  late PlyFrame _frame;

  // The active frame index
  int _frameIndex = 0;

  // Total millis into the frame
  double _framePos = 0;

  // Flag to indicate whether the animation is playing
  bool _playing = false;

  final Paint _paint = Paint();

  @override
  FutureOr<void> onLoad() async {
    _image = await Images().load("$name.png");
    _data = await PlySpriteData.create(name);
    _anim = _data.animations.values.first;
    reset();
    play();
    return super.onLoad();
  }

  /// Reset current animation back to the start
  void reset() {
    _animForward = _anim.direction != PlyDirection.reverse;
    if (_animForward) {
      _frameIndex = 0;
    } else {
      _frameIndex = _anim.frames.length - 1;
    }
    _frame = _anim.frames[_frameIndex];
    _framePos = 0;
  }

  /// Play an animation by [name]. If no [name] is specified will continue
  /// playing the current animation. By default this is the first animation
  /// in the file.
  void play([String? name]) {
    if (name != null) {
      final anim = _data.animations[name] ?? _data.animations.values.first;
      if (anim != _anim) {
        _anim = anim;
        reset();
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
      if (_anim.direction == PlyDirection.reverse) {
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
            if (_anim.direction == PlyDirection.pingpong) {
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
            if (_anim.direction == PlyDirection.pingpong) {
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
      //print("render frame with ${_frame.plys.length} plys");
      for (final ply in _frame.plys) {
        //print("  ${ply.src} => ${ply.dst}");
        canvas.drawImageRect(_image, ply.src, ply.dst, _paint);
      }
    }
    super.render(canvas);
  }
}

enum PlyOrientation {
  normal(0),
  flipH(1),
  flipV(2),
  rotate90(4),
  rotate180(1 & 4),
  rotate270(1 & 2 & 4);

  const PlyOrientation(this.value);
  final int value;

  static PlyOrientation getByValue(int i) {
    return PlyOrientation.values.firstWhere((x) => x.value == i);
  }
}

enum PlyDirection {
  forward(0),
  reverse(1),
  pingpong(2);

  const PlyDirection(this.value);
  final int value;

  static PlyDirection getByValue(int i) {
    return PlyDirection.values.firstWhere((x) => x.value == i);
  }
}

class Ply {
  Ply(this.orientation, this.src, double x, double y) : dst = Rect.fromLTWH(x, y, src.width, src.height) {
    print(
        "    Ply (${src.left}, ${src.top}, ${src.width}, ${src.height}) to (${dst.left}, ${dst.top}, ${dst.width}, ${dst.height})");
  }
  final PlyOrientation orientation;
  final Rect src;
  final Rect dst;
}

class PlyFrame {
  PlyFrame(this.duration);
  final double duration;
  final List<Ply> plys = [];
}

class PlyAnimation {
  PlyAnimation(this.direction);
  final PlyDirection direction;
  final List<PlyFrame> frames = [];
}

class PlySpriteData {
  static final Map<String, PlySpriteData> _cache = {};

  static FutureOr<PlySpriteData> create(String name) async {
    if (!_cache.containsKey(name)) {
      final data = PlySpriteData();
      final json = jsonDecode(await rootBundle.loadString("${Images().prefix}$name.json"));
      data.width = json['width'];
      data.height = json['height'];
      for (final part in json['parts']) {
        final r = Rect.fromLTWH(
          part['x'].toDouble(),
          part['y'].toDouble(),
          part['width'].toDouble(),
          part['height'].toDouble(),
        );
        data.parts.add(r);
        print("Part (${r.left}, ${r.top}, ${r.width}, ${r.height})");
      }
      json['animations'].forEach((name, animData) {
        final anim = PlyAnimation(PlyDirection.getByValue(animData['direction']));
        animData['frames'].forEach((frameData) {
          final frame = PlyFrame(frameData['duration']);
          frameData['parts'].forEach((partData) {
            frame.plys.add(Ply(
              PlyOrientation.getByValue(partData['orientation']),
              data.parts[partData['index']],
              partData['x'].toDouble(),
              partData['y'].toDouble(),
            ));
          });
          anim.frames.add(frame);
        });
        data.animations[name] = anim;
      });
      _cache[name] = data;
    }
    return _cache[name]!;
  }

  late final int width;
  late final int height;
  final List<Rect> parts = [];
  final Map<String, PlyAnimation> animations = {};
}
